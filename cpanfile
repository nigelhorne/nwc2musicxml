# Generated from Makefile.PL using makefilepl2cpanfile

requires 'perl', '5.036';

requires 'Carp';
requires 'Compress::Zlib';
requires 'File::Basename';
requires 'File::Find';
requires 'File::Path';
requires 'File::Spec';
requires 'Getopt::Long';
requires 'Object::Configure';
requires 'Params::Get';
requires 'Params::Validate::Strict';
requires 'Pod::Usage';
requires 'Readonly';
requires 'autodie';
requires 'strict';
requires 'warnings';

on 'test' => sub {
	requires 'IPC::System::Simple';
	requires 'Test::Exception';
	requires 'Test::Most';
};

on 'develop' => sub {
	requires 'Devel::Cover';
	requires 'Perl::Critic';
	requires 'Test::Pod';
	requires 'Test::Pod::Coverage';
};
