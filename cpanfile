# Generated from Makefile.PL using makefilepl2cpanfile

requires 'perl', '5.036';

requires 'Carp';
requires 'Compress::Zlib';
requires 'File::Basename';
requires 'File::Find';
requires 'File::Path';
requires 'File::Spec';
requires 'Getopt::Long';
requires 'Params::Get';
requires 'Params::Validate';
requires 'Pod::Usage';
requires 'Readonly';
requires 'autodie';
requires 'strict';
requires 'warnings';

on 'test' => sub {
	requires 'Test::Exception';
	requires 'Test::More', '0.98';
};

on 'develop' => sub {
	requires 'Devel::Cover';
	requires 'Perl::Critic';
	requires 'Test::Pod';
	requires 'Test::Pod::Coverage';
};
