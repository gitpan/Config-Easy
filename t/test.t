use Test;

BEGIN { plan tests => 24 }

use Config::Easy 't/conf';

ok($C{name} eq "Jon");
ok($C{age} == 54);
ok("@{$C{colors}}" eq "red green yellow");
ok("@{$C{colors2}}" eq "red green yellow");
ok("@{$C{nums}}" eq "3 4 5");
ok($C{mline} eq "1\n2\n3\n");
ok($C{mline2} eq "1\n 2 \n3");
ok($C{phrase} eq "  this is # real good  ");
ok($C{ids} eq "23 34 4556");
ok($C{aisle}{paper} eq "4a");
ok($C{aisle2}{paper} eq "4a");
ok($C{sentence} eq "I am Jon aged 54.");

ok($C{path} eq '/a/b/c.$date.gz');
our $date = "20040210";
our $time = "12:01:09";
config_eval 'path';
ok($C{path} eq "/a/b/c.20040210.gz");

ok($C{trigger} eq '/trig/d.$time.gz');
config_eval;
ok($C{trigger} eq '/trig/d.12:01:09.gz');

use FindBin;
use lib "$FindBin::Bin";
use Mod;

ok(Mod::status eq 'bugged');
ok(Mod::status ne 'ugged');

$c = Config::Easy->new('t/conf1');
ok(defined $c);
ok($c->get('food') eq 'fruit');
($fo, $dr) = $c->get('food', 'drink');
ok($fo eq 'fruit' && $dr eq 'beer');
%hash = $c->get;
ok($hash{food} eq "fruit");
$d = Config::Easy->new('t/conf2');
ok(defined $d);
ok($d->get('comida') eq $c->get("food"));
