use Test;

BEGIN { plan tests => 4 }

BEGIN {
	@ARGV = split /\s+/, "-l blah -F t/conf name=Terri age=34 -- status=fine";
}

use FindBin;
use Config::Easy "$FindBin::Bin/conf1";

ok($C{name} eq "Terri");
ok($C{age} == 34);
ok("@ARGV" eq "-l blah -- status=fine");
ok($C{status} eq 'bugged');
