use Test;

BEGIN { plan tests => 2 }

BEGIN {
	@ARGV = split /\s+/, "name=Terri age=34 -- status=fine";
}

use Config::Easy();

$c = Config::Easy->new('t/conf');
$c->args;
ok($c->get("name") eq "Terri" and $ARGV[0] eq '--');

#
# sentence has $name, $age interpolated at the first 
# call to get() - after the call to args().
#
ok($c->get("sentence") eq "I am Terri aged 34.");
