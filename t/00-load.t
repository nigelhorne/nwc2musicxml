use strict;
use warnings;

use Test::More tests => 8;

BEGIN {
	use_ok 'NWC2MusicXML';
	use_ok 'NWC2MusicXML::NWC';
	use_ok 'NWC2MusicXML::Parser';
	use_ok 'NWC2MusicXML::Score';
	use_ok 'NWC2MusicXML::Staff';
	use_ok 'NWC2MusicXML::Event';
	use_ok 'NWC2MusicXML::MusicXML';
	use_ok 'NWC2MusicXML::Diagnostics';
}

diag "NWC2MusicXML $NWC2MusicXML::VERSION loaded";
