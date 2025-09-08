# $Id: 01-col-inheritance.t 989 2005-09-23 19:58:01Z btrott $

use strict;
use warnings;

use lib 't/lib';

$Data::ObjectDriver::DEBUG = 0;
use Test::More;
use DodTestUtil;

BEGIN { DodTestUtil->check_driver }

plan tests => 13;

setup_dbs({
    global => [ qw( wines ) ],
});

use Wine;
use Storable;

my $wine = Wine->new;
$wine->name("Saumur Champigny, Le Grand Clos 2001");
$wine->rating(4);

## generate some binary data (SQL_BLOB / MEDIUMBLOB)
my $glouglou = { tanin => "beaucoup", caudalies => "4" };
$wine->binchar("xxx\0yyy");
$wine->content(Storable::nfreeze($glouglou));
ok($wine->save, 'Object saved successfully');

my $wine_id = $wine->id;
undef $wine;
$wine = Wine->lookup($wine_id); 

ok $wine;
is_deeply Storable::thaw($wine->content), $glouglou;
SKIP: {
    skip "Please upgrade to DBD::SQLite 1.11", 1
        if $DBD::SQLite::VERSION < 1.11;
    is $wine->binchar, "xxx\0yyy";
};

## SQL_VARBINARY test (for binary CHAR)
my @results = Wine->search({ binchar => "xxx\0yyy"});
is scalar @results, 1;
is $results[0]->rating, 4;
is $results[0]->name, "Saumur Champigny, Le Grand Clos 2001";

## Test Bulk Loading
Wine->bulk_insert(['name', 'rating'], [['Caymus', 4], ['Thunderbird', 1], ['Stags Leap', 3]]);

my ($result) = Wine->search({name => 'Caymus'});
ok $result, 'Found Caymus';
is $result->rating, 4, 'Caymus is a 4';

($result) = Wine->search({name => 'Thunderbird'});
ok $result, 'Found Thunderbird';
is $result->rating, 1, 'Thunderbird is a 1';

($result) = Wine->search({name => 'Stags Leap'});
ok $result, 'Found Stags Leap';
is $result->rating, 3, 'Stags Leap is a 3';

END {
    disconnect_all(qw( Wine ));
    teardown_dbs(qw( global ));
}
