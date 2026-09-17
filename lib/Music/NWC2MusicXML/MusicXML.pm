package Music::NWC2MusicXML::MusicXML;

use strict;
use warnings;
use autodie qw(:all);

our $VERSION = '0.01';

use Carp qw(croak carp);
use Readonly;
use Params::Validate qw(validate_with SCALAR HASHREF);
use Params::Get;
use Music::NWC2MusicXML::Score;

# ---------------------------------------------------------------------------
# MusicXML structural constants
# ---------------------------------------------------------------------------

# MusicXML version targeted (supported by MuseScore 3+)
Readonly::Scalar my $MUSICXML_VERSION => '4.0';

# DOCTYPE public/system identifiers
Readonly::Scalar my $DOCTYPE_PUBLIC =>
	'-//Recordare//DTD MusicXML 4.0 Partwise//EN';
Readonly::Scalar my $DOCTYPE_SYSTEM =>
	'http://www.musicxml.org/dtds/partwise.dtd';

# Default divisions per quarter note used as a fallback; the actual value is
# computed per-score from the LCM of all note-duration denominators.
Readonly::Scalar my $DEFAULT_DIVISIONS => 24;

# Maximum number of simultaneous open slurs per staff
Readonly::Scalar my $MAX_SLUR_NUMBER => 6;

# ---------------------------------------------------------------------------
# Clef mappings: NWC clef name -> { sign, line, [clef-octave-change] }
# ---------------------------------------------------------------------------
Readonly::Hash my %CLEF_MAP => (
	Treble     => { sign => 'G', line => 2 },
	Bass       => { sign => 'F', line => 4 },
	Alto       => { sign => 'C', line => 3 },
	Tenor      => { sign => 'C', line => 4 },
	Percussion => { sign => 'percussion' },
	Tab        => { sign => 'TAB' },
);

# ---------------------------------------------------------------------------
# Articulation mappings: NWC articulation name -> MusicXML element name
# ---------------------------------------------------------------------------
Readonly::Hash my %ARTICULATION_MAP => (
	staccato  => 'staccato',
	accent    => 'accent',
	tenuto    => 'tenuto',
	marcato   => 'strong-accent',
	fermata   => 'fermata',
	trill     => 'trill-mark',
	mordent   => 'mordent',
	turn      => 'turn',
	staccatissimo => 'staccatissimo',
);

# ---------------------------------------------------------------------------
# Dynamic markings: NWC -> MusicXML element
# ---------------------------------------------------------------------------
Readonly::Hash my %DYNAMIC_MAP => map { $_ => $_ }
	qw(pppp ppp pp p mp mf f ff fff ffff);

# ---------------------------------------------------------------------------
# Barline style mapping
# ---------------------------------------------------------------------------
Readonly::Hash my %BARLINE_MAP => (
	normal         => 'regular',
	double         => 'light-light',
	final          => 'light-heavy',
	'Section Close'=> 'light-heavy',
	repeat_start   => 'heavy-light',
	repeat_end     => 'light-heavy',
);

# ---------------------------------------------------------------------------
# Pitch-conversion constants
# ---------------------------------------------------------------------------

# Reference note (step_index, octave) for NWC position 0 = top line of staff.
# Step indices: C=0, D=1, E=2, F=3, G=4, A=5, B=6
# Verified against Pilgrim.nwc: Bass pos -7 = A2 (A-drone), Treble pos -9 = D4 (tonic).
Readonly::Hash my %CLEF_REF => (
	Treble     => [ 3, 5 ],   # F5
	Bass       => [ 5, 3 ],   # A3
	Alto       => [ 4, 4 ],   # G4
	Tenor      => [ 2, 4 ],   # E4
	Percussion => [ 3, 5 ],   # F5 (treat as treble)
	Tab        => [ 3, 5 ],   # F5 (treat as treble)
);

# Diatonic step names indexed 0-6
Readonly::Array my @STEP_NAMES => qw(C D E F G A B);

# Circle-of-fifths order: sharps = F C G D A E B; flats = B E A D G C F
Readonly::Array my @SHARP_STEPS => ( 3, 0, 4, 1, 5, 2, 6 );
Readonly::Array my @FLAT_STEPS  => ( 6, 2, 5, 1, 4, 0, 3 );

# NWC base-duration name -> MusicXML type string
Readonly::Hash my %NWC_TYPE_MAP => (
	Whole  => 'whole',
	Half   => 'half',
	'4th'  => 'quarter',
	'8th'  => 'eighth',
	'16th' => '16th',
	'32nd' => '32nd',
	'64th' => '64th',
);

Readonly::Hash my %MESSAGES => (
	error_bad_score      => 'generate: argument must be a Music::NWC2MusicXML::Score',
	error_no_staves      => 'Score contains no staves -- cannot generate MusicXML',
	error_write_failed   => 'Cannot write to output: %s',
	error_internal       => 'Internal error: %s',
	warn_unknown_clef    => 'Unrecognised NWC clef %s -- defaulting to Treble',
	warn_unknown_dynamic => 'Unrecognised dynamic marking %s',
	warn_unsupported_art => 'Unsupported articulation %s',
	warn_approx_bar      => 'Bar style %s approximated as regular',
);

=head1 NAME

Music::NWC2MusicXML::MusicXML - MusicXML generator.

=head1 VERSION

0.01

=head1 SYNOPSIS

    use Music::NWC2MusicXML::MusicXML;

    my $gen = Music::NWC2MusicXML::MusicXML->new;
    my $xml = $gen->generate($score);
    print $xml;

=head1 DESCRIPTION

C<Music::NWC2MusicXML::MusicXML> accepts a C<Music::NWC2MusicXML::Score> object (the
internal representation produced by C<Music::NWC2MusicXML::Parser>) and emits a
well-formed, UTF-8-encoded MusicXML 4.0 document.

The generator is deliberately isolated from the parser: it knows nothing
about the NWCTXT format.  All musical decisions have already been encoded
in the Score IR; the generator only needs to serialise them.

=head2 Divisions

MusicXML requires a C<< <divisions> >> value declaring how many ticks
represent one quarter note.  To represent all durations exactly, the
generator computes the least common multiple (LCM) of the denominators of
every rational duration it encounters across the score.  This avoids
arbitrary fixed-size grids that might truncate unusual tuplet durations.

=head2 Voices

Where a staff contains simultaneous events (overlapping start times), the
generator assigns them to MusicXML voices 1 and 2 based on stem direction
hints where available, falling back to a simple greedy assignment.

=cut

# ---------------------------------------------------------------------------
# new
# ---------------------------------------------------------------------------

=head2 new

Construct a generator.

=head3 Arguments

Named parameters:

=over 4

=item C<diagnostics> -- a C<Music::NWC2MusicXML::Diagnostics> instance (optional).

=item C<indent>      -- indentation string, default two spaces (optional).

=back

=head3 Returns

Blessed C<Music::NWC2MusicXML::MusicXML> object.

=head3 API SPECIFICATION

=head4 Input

    diagnostics : Music::NWC2MusicXML::Diagnostics  (optional)
    indent      : SCALAR                     (optional, default '  ')

=head4 Output

    Music::NWC2MusicXML::MusicXML object

=head3 FORMAL SPECIFICATION

 [GeneratorInit]
   diagnostics : Diagnostics
   indent      : String

 (placeholder -- populate with Z calculus as implementation matures)

=cut

sub new {
	my $class = shift;
	my %args  = validate_with(
		params => \@_,
		spec   => {
			diagnostics => { optional => 1 },
			indent      => { type => SCALAR, default => '  ' },
		},
		allow_extra => 0,
	);

	my $self = bless {
		_diagnostics => $args{diagnostics},
		_indent      => $args{indent},
	}, $class;

	return $self;
}

# ---------------------------------------------------------------------------
# Public: generate
# ---------------------------------------------------------------------------

=head2 generate

Generate a MusicXML document from a C<Music::NWC2MusicXML::Score> and return it as
a UTF-8 string.

=head3 Purpose

Top-level entry point for MusicXML generation.  Orchestrates the emission of
the XML declaration, DOCTYPE, score-partwise root, part-list, and individual
parts.

=head3 Arguments

=over 4

=item C<$score> -- a C<Music::NWC2MusicXML::Score> object (required).

=back

=head3 Returns

Scalar string containing the complete MusicXML document (UTF-8).

=head3 Side Effects

Issues warnings via C<diagnostics> for unsupported features.
Croaks on fatal structural errors.

=head3 Usage Example

    my $xml = $gen->generate($score);
    open my $fh, '>:encoding(UTF-8)', 'out.musicxml';
    print $fh $xml;
    close $fh;

=head3 API SPECIFICATION

=head4 Input

    $score : Music::NWC2MusicXML::Score (required)

=head4 Output

    SCALAR (UTF-8 MusicXML document string)

=head3 MESSAGES

| Code              | Meaning                             | Resolution                       |
|-------------------|-------------------------------------|----------------------------------|
| error_bad_score   | Argument is not a Score object      | Pass a proper Score              |
| error_no_staves   | Score has no staves                 | Ensure parser succeeded          |
| warn_unknown_clef | NWC clef has no known MusicXML map  | Treble used as fallback          |

=head3 FORMAL SPECIFICATION

 [Generate]
   score? : Score
   ----------
   xml!   : MusicXMLDocument

 (placeholder)

=cut

sub generate {
	my ($self, $score) = @_;

	croak _fmt_msg('error_bad_score')
		unless ref($score) && $score->isa('Music::NWC2MusicXML::Score');

	croak _fmt_msg('error_no_staves')
		unless $score->staff_count > 0;

	# Calculate the divisions value from all note durations in the score.
	my $divisions = $self->_calculate_divisions($score);

	my @out;

	push @out, '<?xml version="1.0" encoding="UTF-8"?>';
	push @out, sprintf('<!DOCTYPE score-partwise PUBLIC "%s" "%s">',
		$DOCTYPE_PUBLIC, $DOCTYPE_SYSTEM);
	push @out, sprintf('<score-partwise version="%s">', $MUSICXML_VERSION);

	push @out, $self->_emit_work($score->metadata);
	push @out, $self->_emit_identification($score->metadata);
	push @out, $self->_emit_part_list($score->staves);
	push @out, $self->_emit_parts($score->staves, $divisions);

	push @out, '</score-partwise>';

	return join("\n", @out) . "\n";
}

# ---------------------------------------------------------------------------
# Private: top-level sections
# ---------------------------------------------------------------------------

sub _emit_work {
	my ($self, $meta) = @_;
	my @out;
	my $i = $self->{_indent};
	push @out, '<work>';
	push @out, "${i}<work-title>" . _xml_escape($meta->{Title} // '') . '</work-title>'
		if $meta->{Title};
	push @out, '</work>';
	return @out;
}

sub _emit_identification {
	my ($self, $meta) = @_;
	my @out;
	my $i = $self->{_indent};
	push @out, '<identification>';
	push @out, "${i}<creator type=\"composer\">"
		. _xml_escape($meta->{Author} // '') . '</creator>'
		if $meta->{Author};
	push @out, "${i}<creator type=\"lyricist\">"
		. _xml_escape($meta->{Lyricist} // '') . '</creator>'
		if $meta->{Lyricist};
	push @out, "${i}<rights>"
		. _xml_escape($meta->{Copyright} // '') . '</rights>'
		if $meta->{Copyright};
	push @out, "${i}<encoding>";
	push @out, "${i}${i}<software>Music::NWC2MusicXML $VERSION</software>";
	push @out, "${i}</encoding>";
	push @out, '</identification>';
	return @out;
}

sub _emit_part_list {
	my ($self, $staves) = @_;
	my @out;
	my $i = $self->{_indent};
	push @out, '<part-list>';
	my $part_id = 1;
	for my $staff (@$staves) {
		my $id   = "P$part_id";
		my $name = _xml_escape($staff->name);
		push @out, "${i}<score-part id=\"$id\">";
		push @out, "${i}${i}<part-name>$name</part-name>";
		my $instr = $staff->instrument;
		if ($instr && $instr->{name}) {
			push @out, "${i}${i}<score-instrument id=\"${id}-I1\">";
			push @out, "${i}${i}${i}<instrument-name>"
				. _xml_escape($instr->{name}) . '</instrument-name>';
			push @out, "${i}${i}</score-instrument>";
			if (defined $instr->{patch}) {
				push @out, "${i}${i}<midi-instrument id=\"${id}-I1\">";
				push @out, "${i}${i}${i}<midi-channel>1</midi-channel>";
				push @out, "${i}${i}${i}<midi-program>"
					. ($instr->{patch} + 1) . '</midi-program>';
				push @out, "${i}${i}</midi-instrument>";
			}
		}
		push @out, "${i}</score-part>";
		$part_id++;
	}
	push @out, '</part-list>';
	return @out;
}

sub _emit_parts {
	my ($self, $staves, $divisions) = @_;
	my @out;
	my $part_id = 1;
	for my $staff (@$staves) {
		push @out, $self->_emit_part("P$part_id", $staff, $divisions);
		$part_id++;
	}
	return @out;
}

sub _emit_part {
	my ($self, $id, $staff, $divisions) = @_;
	my @out;

	push @out, "<part id=\"$id\">";

	my $measure_no = 1;
	my @pending    = ();
	my $first      = 1;

	# Current clef and key may change mid-staff via Clef/Key events.
	my $clef       = $staff->initial_clef // 'Treble';
	my $key_fifths = ($staff->initial_key  // {})->{fifths} // 0;
	my $prev_bar   = 'normal';   # style of barline that ended the previous measure

	for my $event (@{ $staff->events }) {
		my $type = $event->type;

		if ($type eq 'Bar') {
			my $bar_style = $event->data->{style} // 'normal';
			push @out, $self->_emit_measure(
				$measure_no++, \@pending, $staff, $divisions,
				$first, $clef, $key_fifths, $prev_bar, $bar_style
			);
			@pending  = ();
			$first    = 0;
			$prev_bar = $bar_style;

		} elsif ($type eq 'Clef') {
			# Update clef for subsequent pitch conversions; also queue for mid-measure attributes
			$clef = $event->data->{nwc_clef} // $clef;

		} elsif ($type eq 'Key') {
			$key_fifths = ($event->data // {})->{fifths} // 0;

		} else {
			push @pending, $event;
		}
	}

	# Flush remaining events after the last barline; always emit at least measure 1
	if (@pending || $measure_no == 1) {
		push @out, $self->_emit_measure(
			$measure_no, \@pending, $staff, $divisions,
			$first, $clef, $key_fifths, $prev_bar, 'normal'
		);
	}

	push @out, "</part>";
	return @out;
}

sub _emit_measure {
	my ($self, $number, $events, $staff, $divisions, $is_first,
	    $clef, $key_fifths, $prev_bar, $bar_style) = @_;
	$clef      //= 'Treble';
	$key_fifths //= 0;
	$prev_bar  //= 'normal';
	$bar_style //= 'normal';

	my @out;
	my $i   = $self->{_indent};
	my $pad = $i;

	push @out, "${pad}<measure number=\"$number\">";

	# Left-side repeat barline when the previous measure ended with MasterRepeatOpen
	if ($prev_bar eq 'MasterRepeatOpen') {
		push @out, "${pad}${i}<barline location=\"left\">";
		push @out, "${pad}${i}${i}<bar-style>heavy-light</bar-style>";
		push @out, "${pad}${i}${i}<repeat direction=\"forward\"/>";
		push @out, "${pad}${i}</barline>";
	}

	# Attributes: divisions, key, time, clef (measure 1 only for now)
	if ($is_first) {
		push @out, $self->_emit_attributes($staff, $divisions, $pad . $i);
	}

	# Emit musical events
	for my $event (@$events) {
		my $type = $event->type;
		if ($type eq 'Note') {
			push @out, $self->_emit_note_event(
				$event, $clef, $key_fifths, $divisions, $pad . $i, 0);
		} elsif ($type eq 'Rest') {
			push @out, $self->_emit_rest_event($event, $divisions, $pad . $i);
		} elsif ($type eq 'Chord') {
			push @out, $self->_emit_chord_event(
				$event, $clef, $key_fifths, $divisions, $pad . $i);
		}
		# Tempo, Dynamic, Text etc. deferred to Phase 4
	}

	# Right-side barline for repeats and double bars
	if ($bar_style eq 'MasterRepeatClose') {
		push @out, "${pad}${i}<barline location=\"right\">";
		push @out, "${pad}${i}${i}<bar-style>light-heavy</bar-style>";
		push @out, "${pad}${i}${i}<repeat direction=\"backward\"/>";
		push @out, "${pad}${i}</barline>";
	} elsif ($bar_style eq 'Double') {
		push @out, "${pad}${i}<barline location=\"right\">";
		push @out, "${pad}${i}${i}<bar-style>light-light</bar-style>";
		push @out, "${pad}${i}</barline>";
	} elsif ($bar_style eq 'SectionClose' || $bar_style eq 'LocalRepeatClose') {
		push @out, "${pad}${i}<barline location=\"right\">";
		push @out, "${pad}${i}${i}<bar-style>light-heavy</bar-style>";
		push @out, "${pad}${i}</barline>";
	}

	push @out, "${pad}</measure>";
	return @out;
}

# ---------------------------------------------------------------------------
# Private: note / rest / chord XML emission
# ---------------------------------------------------------------------------

sub _emit_note_event {
	my ($self, $event, $clef, $key_fifths, $divisions, $pad, $is_chord_member) = @_;
	my $d    = $event->data;
	my @out;
	my $i    = $self->{_indent};

	my $pitch = $self->_pos_to_pitch($d->{nwc_pos} // '0', $clef, $key_fifths);
	my $ticks = _rational_to_ticks($event->duration, $divisions);
	my $type  = $NWC_TYPE_MAP{ $d->{base_dur} // '4th' } // 'quarter';

	push @out, "${pad}<note>";
	push @out, "${pad}${i}<chord/>" if $is_chord_member;
	push @out, "${pad}${i}<pitch>";
	push @out, "${pad}${i}${i}<step>$pitch->{step}</step>";
	push @out, "${pad}${i}${i}<alter>$pitch->{alter}</alter>" if $pitch->{alter};
	push @out, "${pad}${i}${i}<octave>$pitch->{octave}</octave>";
	push @out, "${pad}${i}</pitch>";
	push @out, "${pad}${i}<duration>$ticks</duration>";
	push @out, "${pad}${i}<voice>1</voice>";
	push @out, "${pad}${i}<type>$type</type>";
	push @out, "${pad}${i}<dot/>" for 1 .. ($d->{dots} // 0);
	push @out, "${pad}${i}<accidental>$pitch->{accidental}</accidental>"
		if $pitch->{accidental};
	push @out, "${pad}</note>";
	return @out;
}

sub _emit_rest_event {
	my ($self, $event, $divisions, $pad) = @_;
	my $d    = $event->data;
	my @out;
	my $i    = $self->{_indent};

	my $ticks = _rational_to_ticks($event->duration, $divisions);
	my $type  = $NWC_TYPE_MAP{ $d->{base_dur} // '4th' } // 'quarter';

	push @out, "${pad}<note>";
	push @out, "${pad}${i}<rest/>";
	push @out, "${pad}${i}<duration>$ticks</duration>";
	push @out, "${pad}${i}<voice>1</voice>";
	push @out, "${pad}${i}<type>$type</type>";
	push @out, "${pad}${i}<dot/>" for 1 .. ($d->{dots} // 0);
	push @out, "${pad}</note>";
	return @out;
}

sub _emit_chord_event {
	my ($self, $event, $clef, $key_fifths, $divisions, $pad) = @_;
	my $d   = $event->data;
	my @out;

	my $positions = $d->{nwc_positions} // ['0'];
	my $first     = 1;

	for my $pos_str (@$positions) {
		push @out, $self->_emit_note_event(
			_chord_note_event($event, $pos_str),
			$clef, $key_fifths, $divisions, $pad, !$first
		);
		$first = 0;
	}
	return @out;
}

# Build a lightweight synthetic Note event for a single chord member.
sub _chord_note_event {
	my ($chord_event, $pos_str) = @_;
	my $d = $chord_event->data;
	return bless {
		_type     => 'Note',
		_duration => $chord_event->duration,
		_data     => {
			nwc_pos  => $pos_str,
			base_dur => $d->{base_dur},
			dots     => $d->{dots},
		},
	}, ref($chord_event);
}

# ---------------------------------------------------------------------------
# Private: pitch conversion
# ---------------------------------------------------------------------------

# Convert an NWC position string (e.g. "#-6", "b3", "-9^") to a MusicXML
# pitch descriptor { step, octave, alter, accidental }.
#
# Position 0 = top line of the staff (clef-specific reference note).
# Negative positions go DOWN the staff; positive positions go UP.
# Formula: diatonic_index = ref_oct*7 + ref_step + pos_num
# Verified: Bass pos -7 = A2 (dominant drone in D minor). Treble pos -9 = D4 (tonic).
sub _pos_to_pitch {
	my ($self, $pos_str, $clef, $key_fifths) = @_;
	$pos_str    //= '0';
	$clef       //= 'Treble';
	$key_fifths //= 0;

	# Parse: optional accidental prefix + signed integer + optional tie marker
	my ($acc_prefix, $pos_num) = ('', 0);
	if ($pos_str =~ /^([#bnx]*)(-?\d+)\^?$/) {
		($acc_prefix, $pos_num) = ($1, $2 + 0);
	}

	my $ref      = $CLEF_REF{$clef} // $CLEF_REF{Treble};
	my $index    = $ref->[1] * 7 + $ref->[0] + $pos_num;

	# Floor division: octave = floor(index / 7), step_i = index mod 7 in [0,6]
	my $octave   = int($index / 7);
	$octave--    if $index < 0 && ($index % 7) != 0;
	my $step_i   = $index - $octave * 7;

	my $step     = $STEP_NAMES[$step_i];
	my $key_alt  = _key_alter_for_step($step_i, $key_fifths);

	my ($alter, $accidental);
	if    ($acc_prefix eq '')         { $alter =  $key_alt; $accidental = undef       }
	elsif ($acc_prefix eq '#')        { $alter =  1;        $accidental = 'sharp'     }
	elsif ($acc_prefix eq '##')       { $alter =  2;        $accidental = 'double-sharp' }
	elsif ($acc_prefix eq 'x')        { $alter =  2;        $accidental = 'double-sharp' }
	elsif ($acc_prefix eq 'b')        { $alter = -1;        $accidental = 'flat'      }
	elsif ($acc_prefix eq 'bb')       { $alter = -2;        $accidental = 'double-flat'  }
	elsif ($acc_prefix eq 'n')        { $alter =  0;        $accidental = 'natural'   }
	else                              { $alter =  $key_alt; $accidental = undef       }

	return { step => $step, octave => $octave, alter => $alter, accidental => $accidental };
}

sub _key_alter_for_step {
	my ($step_i, $key_fifths) = @_;
	return 0 unless $key_fifths;

	if ($key_fifths > 0) {
		my $n = $key_fifths > 7 ? 7 : $key_fifths;
		for my $k (0 .. $n - 1) {
			return 1 if $SHARP_STEPS[$k] == $step_i;
		}
	} else {
		my $n = (-$key_fifths) > 7 ? 7 : (-$key_fifths);
		for my $k (0 .. $n - 1) {
			return -1 if $FLAT_STEPS[$k] == $step_i;
		}
	}
	return 0;
}

sub _rational_to_ticks {
	my ($rational, $divisions) = @_;
	return int($rational->[0] * $divisions / $rational->[1] + 0.5);
}

sub _emit_attributes {
	my ($self, $staff, $divisions, $pad) = @_;
	my @out;
	my $i = $self->{_indent};

	push @out, "${pad}<attributes>";
	push @out, "${pad}${i}<divisions>$divisions</divisions>";

	if (my $key = $staff->initial_key) {
		push @out, "${pad}${i}<key>";
		push @out, "${pad}${i}${i}<fifths>$key->{fifths}</fifths>";
		push @out, "${pad}${i}</key>";
	}

	if (my $ts = $staff->initial_timesig) {
		push @out, "${pad}${i}<time>";
		push @out, "${pad}${i}${i}<beats>$ts->{beats}</beats>";
		push @out, "${pad}${i}${i}<beat-type>$ts->{beat_type}</beat-type>";
		push @out, "${pad}${i}</time>";
	}

	if (my $clef_name = $staff->initial_clef) {
		push @out, "${pad}${i}<clef>";
		my $clef = $CLEF_MAP{$clef_name};
		unless (defined $clef) {
			carp _fmt_msg('warn_unknown_clef', $clef_name);
			$clef = $CLEF_MAP{Treble};
		}
		push @out, "${pad}${i}${i}<sign>$clef->{sign}</sign>";
		push @out, "${pad}${i}${i}<line>$clef->{line}</line>"
			if defined $clef->{line};
		push @out, "${pad}${i}</clef>";
	}

	push @out, "${pad}</attributes>";
	return @out;
}

# ---------------------------------------------------------------------------
# Private: divisions calculation
# ---------------------------------------------------------------------------

# Strategy: collect the denominator of every rational duration encountered
# across all staves, then compute their LCM.  The divisions value is that LCM,
# guaranteeing exact integer representation for every duration tick count.

sub _calculate_divisions {
	my ($self, $score) = @_;

	my @denoms;
	for my $staff (@{ $score->staves }) {
		for my $event (@{ $staff->events }) {
			my $dur = $event->duration;
			push @denoms, $dur->[1] if $dur->[1] > 0;
		}
	}

	return $DEFAULT_DIVISIONS unless @denoms;

	my $lcm = $denoms[0];
	for my $d (@denoms[1..$#denoms]) {
		$lcm = _lcm($lcm, $d);
	}

	return $lcm;
}

# ---------------------------------------------------------------------------
# Private: XML helpers
# ---------------------------------------------------------------------------

sub _xml_escape {
	my ($s) = @_;
	return '' unless defined $s;
	$s =~ s/&/&amp;/g;
	$s =~ s/</&lt;/g;
	$s =~ s/>/&gt;/g;
	$s =~ s/"/&quot;/g;
	$s =~ s/'/&apos;/g;
	return $s;
}

sub _lcm {
	my ($a, $b) = @_;
	return $a / _gcd($a, $b) * $b;
}

sub _gcd {
	my ($a, $b) = @_;
	($a, $b) = ($b, $a % $b) while $b;
	return $a;
}

sub _fmt_msg {
	my ($key, @args) = @_;
	croak "Unknown message key: $key" unless exists $MESSAGES{$key};
	return sprintf $MESSAGES{$key}, @args;
}

1;

__END__

=head1 DIAGNOSTICS

=head3 MESSAGES

| Code                | Meaning                              | Resolution                     |
|---------------------|--------------------------------------|--------------------------------|
| error_bad_score     | Argument is not a Score              | Construct Score via Parser     |
| error_no_staves     | Score has no staves                  | Parser may have failed         |
| warn_unknown_clef   | NWC clef not in CLEF_MAP             | Will default to Treble         |
| warn_unknown_dynamic| NWC dynamic not in DYNAMIC_MAP       | Warning emitted; ignored       |
| warn_unsupported_art| NWC articulation not in map          | Warning emitted; ignored       |

=head1 LIMITATIONS

=over 4

=item * Individual note/rest XML emission is stubbed (Phase 3).

=item * Voice assignment for simultaneous events is stubbed (Phase 3).

=item * Tuplet C<< <time-modification> >> and C<< <tuplet> >> elements are stubbed (Phase 4).

=item * Slur/tie number management is stubbed (Phase 4).

=item * Lyric emission is stubbed (Phase 4).

=item * Flow-control (repeats, Coda, Segno, etc.) is stubbed (Phase 5).

=back

=head1 AUTHOR

Nigel Horne C<< <nigel.horne@gmail.com> >>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
