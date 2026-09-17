use strict;
use warnings;

use Test::More;
use Test::Exception;

use lib 'lib';
use NWC2MusicXML::MusicXML;
use NWC2MusicXML::Score;
use NWC2MusicXML::Staff;
use NWC2MusicXML::Event;

# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------
{
	my $gen = NWC2MusicXML::MusicXML->new;
	isa_ok $gen, 'NWC2MusicXML::MusicXML';
}

# ---------------------------------------------------------------------------
# generate: bad argument
# ---------------------------------------------------------------------------
{
	my $gen = NWC2MusicXML::MusicXML->new;
	throws_ok { $gen->generate('not a score') }
		qr/NWC2MusicXML::Score/i,
		'generate with non-Score croaks';
}

# ---------------------------------------------------------------------------
# generate: empty score (no staves)
# ---------------------------------------------------------------------------
{
	my $gen   = NWC2MusicXML::MusicXML->new;
	my $score = NWC2MusicXML::Score->new;
	throws_ok { $gen->generate($score) }
		qr/no staves/i,
		'generate with no staves croaks';
}

# ---------------------------------------------------------------------------
# generate: minimal single-staff score
# ---------------------------------------------------------------------------
{
	my $staff = NWC2MusicXML::Staff->new(
		name => 'Violin I',
	);
	$staff->set_initial_clef('Treble');
	$staff->set_initial_key({ signature => 'C', tonic => 'C', fifths => 0 });
	$staff->set_initial_timesig({ beats => 4, beat_type => 4 });

	my $score = NWC2MusicXML::Score->new(
		metadata => { Title => 'Test Score', Author => 'Test Author' },
	);
	$score->add_staff($staff);

	my $gen = NWC2MusicXML::MusicXML->new;
	my $xml;
	lives_ok { $xml = $gen->generate($score) } 'generate does not croak';

	ok defined $xml && length $xml, 'generate returns non-empty string';
	like $xml, qr/<?xml/,              'output starts with XML declaration';
	like $xml, qr/score-partwise/,     'output contains score-partwise element';
	like $xml, qr/Test Score/,         'title present in output';
	like $xml, qr/Test Author/,        'author present in output';
	like $xml, qr/Violin I/,           'staff name present in output';
	like $xml, qr/<divisions>/,        'divisions element present';
	like $xml, qr/<key>/,              'key element present';
	like $xml, qr/<time>/,             'time element present';
	like $xml, qr/<clef>/,             'clef element present';
}

# ---------------------------------------------------------------------------
# XML escaping
# ---------------------------------------------------------------------------
{
	my $staff = NWC2MusicXML::Staff->new(name => 'A & B <Test>');
	$staff->set_initial_clef('Treble');
	$staff->set_initial_key({ signature => 'C', tonic => 'C', fifths => 0 });
	$staff->set_initial_timesig({ beats => 4, beat_type => 4 });

	my $score = NWC2MusicXML::Score->new(
		metadata => { Title => 'Title with "quotes" & ampersands' },
	);
	$score->add_staff($staff);

	my $xml = NWC2MusicXML::MusicXML->new->generate($score);

	unlike $xml, qr/&(?!amp;|lt;|gt;|quot;|apos;)/,
		'raw ampersands are escaped';
	unlike $xml, qr/<(?!(?:[a-z\/!?]))/i,
		'raw angle brackets are escaped in text content';
}

done_testing;
