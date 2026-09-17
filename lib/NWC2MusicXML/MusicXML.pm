package NWC2MusicXML::MusicXML;

use strict;
use warnings;
use autodie qw(:all);

our $VERSION = '0.01';

use Carp qw(croak carp);
use Readonly;
use Params::Validate qw(validate_with SCALAR HASHREF);
use Params::Get;
use NWC2MusicXML::Score;

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

Readonly::Hash my %MESSAGES => (
	error_bad_score      => 'generate: argument must be a NWC2MusicXML::Score',
	error_no_staves      => 'Score contains no staves -- cannot generate MusicXML',
	error_write_failed   => 'Cannot write to output: %s',
	error_internal       => 'Internal error: %s',
	warn_unknown_clef    => 'Unrecognised NWC clef %s -- defaulting to Treble',
	warn_unknown_dynamic => 'Unrecognised dynamic marking %s',
	warn_unsupported_art => 'Unsupported articulation %s',
	warn_approx_bar      => 'Bar style %s approximated as regular',
);

=head1 NAME

NWC2MusicXML::MusicXML - MusicXML generator.

=head1 VERSION

0.01

=head1 SYNOPSIS

    use NWC2MusicXML::MusicXML;

    my $gen = NWC2MusicXML::MusicXML->new;
    my $xml = $gen->generate($score);
    print $xml;

=head1 DESCRIPTION

C<NWC2MusicXML::MusicXML> accepts a C<NWC2MusicXML::Score> object (the
internal representation produced by C<NWC2MusicXML::Parser>) and emits a
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

=item C<diagnostics> -- a C<NWC2MusicXML::Diagnostics> instance (optional).

=item C<indent>      -- indentation string, default two spaces (optional).

=back

=head3 Returns

Blessed C<NWC2MusicXML::MusicXML> object.

=head3 API SPECIFICATION

=head4 Input

    diagnostics : NWC2MusicXML::Diagnostics  (optional)
    indent      : SCALAR                     (optional, default '  ')

=head4 Output

    NWC2MusicXML::MusicXML object

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

Generate a MusicXML document from a C<NWC2MusicXML::Score> and return it as
a UTF-8 string.

=head3 Purpose

Top-level entry point for MusicXML generation.  Orchestrates the emission of
the XML declaration, DOCTYPE, score-partwise root, part-list, and individual
parts.

=head3 Arguments

=over 4

=item C<$score> -- a C<NWC2MusicXML::Score> object (required).

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

    $score : NWC2MusicXML::Score (required)

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
		unless ref($score) && $score->isa('NWC2MusicXML::Score');

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
	push @out, "${i}${i}<software>NWC2MusicXML $VERSION</software>";
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
	my $i = $self->{_indent};

	push @out, "<part id=\"$id\">";

	# Strategy: walk events, accumulate notes between Bar events into measures.
	# Each Bar event triggers the close of one measure and the open of the next.
	# Initial clef/key/time are emitted in measure 1's attributes block.

	my $measure_no = 1;
	my @pending    = ();    # events in the current measure
	my $first      = 1;

	for my $event (@{ $staff->events }) {
		if ($event->type eq 'Bar') {
			push @out, $self->_emit_measure(
				$measure_no++, \@pending, $staff, $divisions, $first
			);
			@pending = ();
			$first   = 0;
		} else {
			push @pending, $event;
		}
	}

	# Flush remaining events after the last bar line, or emit an empty
	# measure 1 when the staff has no events (ensures the attributes block
	# -- divisions, key, time, clef -- is always written).
	if (@pending || $measure_no == 1) {
		push @out, $self->_emit_measure(
			$measure_no, \@pending, $staff, $divisions, $first
		);
	}

	push @out, "</part>";
	return @out;
}

sub _emit_measure {
	my ($self, $number, $events, $staff, $divisions, $is_first) = @_;
	my @out;
	my $i = $self->{_indent};

	push @out, "${i}<measure number=\"$number\">";

	# Attributes block: emitted in measure 1 (and on attribute-change events)
	if ($is_first) {
		push @out, $self->_emit_attributes($staff, $divisions, $i . $i);
	}

	# TODO Phase 3: emit individual event XML elements from @events
	# For each event, call the appropriate _emit_* method.

	push @out, "${i}</measure>";
	return @out;
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
