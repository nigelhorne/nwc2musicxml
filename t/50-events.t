use strict;
use warnings;

use Test::Most;

use lib 'lib';
use_ok('Music::NWC2MusicXML::Parser');
use_ok('Music::NWC2MusicXML::MusicXML');
use_ok('Music::NWC2MusicXML::Score');
use_ok('Music::NWC2MusicXML::Staff');
use_ok('Music::NWC2MusicXML::Event');

# ---------------------------------------------------------------------------
# Helper: build a minimal NWCTXT with a single staff, initial clef/key/time,
# then any extra lines.  Returns the parsed score.
# ---------------------------------------------------------------------------
sub parse_nwctxt {
	my (@extra_lines) = @_;
	my $nwctxt = join "\n",
		'!NoteWorthyComposer(2.751)',
		'|AddStaff|Name:"Staff"',
		'|Clef|Type:Treble',
		'|Key|Signature:C',
		'|TimeSig|Signature:4/4',
		# A Bar forces subsequent Clef/Key/TimeSig to be mid-staff events
		'|Note|Dur:4th|Pos:0',
		'|Bar|',
		@extra_lines,
		;
	return Music::NWC2MusicXML::Parser->new->parse($nwctxt);
}

# ---------------------------------------------------------------------------
# Dynamic event parsing
# ---------------------------------------------------------------------------
{
	my $score = parse_nwctxt(
		'|Dynamic|Style:mf|Placement:Below',
	);
	my @evs = grep { $_->type eq 'Dynamic' } @{ $score->staves->[0]->events };
	is scalar @evs, 1, 'one Dynamic event parsed';
	is $evs[0]->data->{marking},   'mf',    'Dynamic marking is mf';
	is $evs[0]->data->{placement}, 'Below', 'Dynamic placement stored';
}

# Dynamic with positional style (no Style: key)
{
	my $score = parse_nwctxt('|Dynamic|ff');
	my @evs = grep { $_->type eq 'Dynamic' } @{ $score->staves->[0]->events };
	is scalar @evs, 1, 'positional Dynamic parsed';
}

# ---------------------------------------------------------------------------
# DynVariance (hairpin) event parsing
# ---------------------------------------------------------------------------
{
	my $score = parse_nwctxt(
		'|DynVariance|Style:Crescendo|Placement:Below',
	);
	my @evs = grep { $_->type eq 'DynVariance' } @{ $score->staves->[0]->events };
	is scalar @evs, 1, 'one DynVariance event parsed';
	is $evs[0]->data->{style},     'Crescendo', 'DynVariance style correct';
	is $evs[0]->data->{placement}, 'Below',     'DynVariance placement stored';
}

{
	my $score = parse_nwctxt('|DynVariance|Style:crescOff');
	my @evs = grep { $_->type eq 'DynVariance' } @{ $score->staves->[0]->events };
	is $evs[0]->data->{style}, 'crescOff', 'crescOff style parsed';
}

{
	my $score = parse_nwctxt('|DynVariance|Style:Diminuendo');
	my @evs = grep { $_->type eq 'DynVariance' } @{ $score->staves->[0]->events };
	is $evs[0]->data->{style}, 'Diminuendo', 'Diminuendo style parsed';
}

# ---------------------------------------------------------------------------
# Tempo event parsing and base field
# ---------------------------------------------------------------------------
{
	my $score = parse_nwctxt('|Tempo|Tempo:120|Base:Quarter');
	my @evs = grep { $_->type eq 'Tempo' } @{ $score->staves->[0]->events };
	is scalar @evs, 1, 'one Tempo event parsed';
	is $evs[0]->data->{bpm},  120,       'Tempo BPM correct';
	is $evs[0]->data->{base}, 'Quarter', 'Tempo base correct';
}

# Default base is Quarter when not supplied
{
	my $score = parse_nwctxt('|Tempo|Tempo:80');
	my @evs = grep { $_->type eq 'Tempo' } @{ $score->staves->[0]->events };
	is $evs[0]->data->{base}, 'Quarter', 'Tempo base defaults to Quarter';
}

# Dotted beat unit
{
	my $score = parse_nwctxt('|Tempo|Tempo:60|Base:Dotted Half');
	my @evs = grep { $_->type eq 'Tempo' } @{ $score->staves->[0]->events };
	is $evs[0]->data->{base}, 'Dotted Half', 'Dotted Half base parsed';
}

# ---------------------------------------------------------------------------
# Tempo before TimeSig in staff header -- has_notes fix regression
# ---------------------------------------------------------------------------
# If Tempo is counted as a "note" (old event_count bug), the subsequent
# TimeSig would be treated as a mid-staff event instead of the initial value.
{
	my $nwctxt = join "\n",
		'!NoteWorthyComposer(2.751)',
		'|AddStaff|Name:"Staff"',
		'|Clef|Type:Treble',
		'|Key|Signature:C',
		'|Tempo|Tempo:112',      # Tempo before TimeSig
		'|TimeSig|Signature:3/4',
		;
	my $score = Music::NWC2MusicXML::Parser->new->parse($nwctxt);
	my $ts = $score->staves->[0]->initial_timesig;
	ok defined $ts, 'initial_timesig set when Tempo precedes TimeSig';
	is $ts->{beats},     3, 'beats=3 (Tempo before TimeSig did not displace it)';
	is $ts->{beat_type}, 4, 'beat_type=4';
}

# ---------------------------------------------------------------------------
# MusicXML output: Dynamic rendered as <dynamics>
# ---------------------------------------------------------------------------
{
	my $staff = Music::NWC2MusicXML::Staff->new(name => 'Test');
	$staff->set_initial_clef('Treble');
	$staff->set_initial_key({ signature => 'C', tonic => 'C', fifths => 0 });
	$staff->set_initial_timesig({ beats => 4, beat_type => 4 });
	$staff->add_event(Music::NWC2MusicXML::Event->new(
		type => 'Dynamic',
		data => { marking => 'pp', placement => 'Below' },
	));

	my $score = Music::NWC2MusicXML::Score->new;
	$score->add_staff($staff);

	my $xml = Music::NWC2MusicXML::MusicXML->new->generate($score);
	like $xml, qr/<dynamics>/,  'dynamics element present in output';
	like $xml, qr/<pp\/>/,      'pp dynamic marking present';
}

# ---------------------------------------------------------------------------
# MusicXML output: DynVariance rendered as <wedge>
# ---------------------------------------------------------------------------
{
	my $staff = Music::NWC2MusicXML::Staff->new(name => 'Test');
	$staff->set_initial_clef('Treble');
	$staff->set_initial_key({ signature => 'C', tonic => 'C', fifths => 0 });
	$staff->set_initial_timesig({ beats => 4, beat_type => 4 });
	$staff->add_event(Music::NWC2MusicXML::Event->new(
		type => 'DynVariance',
		data => { style => 'Crescendo', placement => 'Below' },
	));

	my $score = Music::NWC2MusicXML::Score->new;
	$score->add_staff($staff);

	my $xml = Music::NWC2MusicXML::MusicXML->new->generate($score);
	like $xml, qr/wedge type="crescendo"/,  'crescendo wedge in output';
}

# ---------------------------------------------------------------------------
# MusicXML output: Tempo rendered as <metronome> + <sound>
# ---------------------------------------------------------------------------
{
	my $staff = Music::NWC2MusicXML::Staff->new(name => 'Test');
	$staff->set_initial_clef('Treble');
	$staff->set_initial_key({ signature => 'C', tonic => 'C', fifths => 0 });
	$staff->set_initial_timesig({ beats => 4, beat_type => 4 });
	$staff->add_event(Music::NWC2MusicXML::Event->new(
		type => 'Tempo',
		data => { bpm => 132, base => 'Quarter' },
	));

	my $score = Music::NWC2MusicXML::Score->new;
	$score->add_staff($staff);

	my $xml = Music::NWC2MusicXML::MusicXML->new->generate($score);
	like $xml, qr/<metronome/,            'metronome element present';
	like $xml, qr/<per-minute>132</,      'BPM in output';
	like $xml, qr/sound tempo="132"/,     'sound tempo tag present';
	like $xml, qr/<beat-unit>quarter</,   'beat unit is quarter';
}

# Dotted half tempo: sound bpm = 132 * 3 = 396 quarter-note BPM
{
	my $staff = Music::NWC2MusicXML::Staff->new(name => 'Test');
	$staff->set_initial_clef('Treble');
	$staff->set_initial_key({ signature => 'C', tonic => 'C', fifths => 0 });
	$staff->set_initial_timesig({ beats => 4, beat_type => 4 });
	$staff->add_event(Music::NWC2MusicXML::Event->new(
		type => 'Tempo',
		data => { bpm => 60, base => 'Dotted Half' },
	));

	my $score = Music::NWC2MusicXML::Score->new;
	$score->add_staff($staff);

	my $xml = Music::NWC2MusicXML::MusicXML->new->generate($score);
	like $xml, qr/sound tempo="180"/, 'dotted-half 60 BPM = 180 quarter-note BPM in sound tag';
	like $xml, qr/<beat-unit>half</,  'beat-unit is half';
	like $xml, qr/<beat-unit-dot\/>/,  'beat-unit-dot present for dotted value';
}

done_testing();
