use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
	NAME             => 'Music::NWC2MusicXML',
	AUTHOR           => 'Nigel Horne <nigel.horne@gmail.com>',
	VERSION_FROM     => 'lib/Music/NWC2MusicXML.pm',
	ABSTRACT_FROM    => 'lib/Music/NWC2MusicXML.pm',
	LICENSE          => 'perl',
	MIN_PERL_VERSION => '5.036',
	EXE_FILES        => [ 'bin/nwc2musicxml' ],
	PREREQ_PM        => {
		'strict'           => 0,
		'warnings'         => 0,
		'autodie'          => 0,
		'Carp'             => 0,
		'Readonly'         => 0,
		'Params::Validate' => 0,
		'Params::Get'      => 0,
		'Compress::Zlib'   => 0,
		'File::Basename'   => 0,
		'File::Find'       => 0,
		'File::Path'       => 0,
		'File::Spec'       => 0,
		'Getopt::Long'     => 0,
		'Pod::Usage'       => 0,
	},
	TEST_REQUIRES => {
		'Test::More'       => '0.98',
		'Test::Exception'  => 0,
	},
	META_MERGE => {
		'meta-spec' => { version => 2 },
		resources   => {
			repository => {
				type => 'git',
				url  => 'https://github.com/nigelhorne/NWC2MusicXML.git',
				web  => 'https://github.com/nigelhorne/NWC2MusicXML',
			},
			bugtracker => {
				web => 'https://github.com/nigelhorne/NWC2MusicXML/issues',
			},
		},
	},
	dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz' },
	clean => { FILES    => 'Music-NWC2MusicXML-*' },
);
