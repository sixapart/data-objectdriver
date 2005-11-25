# $Id: 01-col-inheritance.t 989 2005-09-23 19:58:01Z btrott $

use strict;

use lib 't/lib';

require 't/lib/db-common.pl';

use Test::More;
unless (eval { require DBD::SQLite }) {
    plan skip_all => 'Tests require DBD::SQLite';
}
plan tests => 3;

setup_dbs({
    global => [ qw( wines ) ],
});

use Wine;
use Storable;

my $wine = Wine->new;
$wine->name("Saumur Champigny, Le Grand Clos 2001");
$wine->rating(4);

# generate some binary data
my $glouglou = { tanin => "beaucoup", caudalies => "4" };
$wine->content(Storable::nfreeze($glouglou));
ok($wine->save, 'Object saved successfully');

my $wine_id = $wine->id;
undef $wine;
$wine = Wine->lookup($wine_id); 

ok $wine;
is_deeply Storable::thaw($wine->content), $glouglou;

teardown_dbs(qw( global ));
