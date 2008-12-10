# $Id: 01-col-inheritance.t 989 2005-09-23 19:58:01Z btrott $

use strict;

use lib 't/lib';

require 't/lib/db-common.pl';

$Data::ObjectDriver::DEBUG = 0;
use Test::More;
unless (eval { require DBD::SQLite }) {
    plan skip_all => 'Tests require DBD::SQLite';
}
plan tests => 50;

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

my $iter;

$iter = Data::ObjectDriver::Iterator->new(sub {});
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

Wine->bulk_insert(['name', 'rating'], [['Caymus', 4], ['Thunderbird', 1], ['Stags Leap', 3]]);


{
    my $result = Wine->result({});

    my $objs = $result->slice(0, 100);
    is @$objs, 4;

    my $rs = $result->slice(0, 2);
    is @$rs, 3;
    for my $r (@$rs) {
        isa_ok $r, 'Wine';
    }
}

$wine = undef; 
my ($result) = Wine->result({name => 'Caymus'});
ok! $result->is_finished;
$wine = $result->next;
ok $wine, 'Found Caymus';
is $wine->name, 'Caymus';
ok ! $result->next; #sets is_finished()
ok $result->is_finished;

# testing iterator
my ($iterator) = $result->iterator([$wine]);
ok(! $iterator->is_finished );
$wine = $iterator->next;
ok $wine, 'Found Caymus';
is $wine->name, 'Caymus';
ok( ! $iterator->next ); 
ok( $iterator->is_finished );

# testing bug in iterator, adding a limit where there was one before shouldn't invalidate results
($iterator) = $result->iterator([$wine]);
$iterator->add_limit(1);
ok(! $iterator->is_finished );
$wine = $iterator->next;
ok $wine, 'Found Caymus';
is $wine->name, 'Caymus';
ok ! $iterator->next; 
ok $iterator->is_finished;


($result) = Wine->result({}, { sort => 'name', direction => 'ascend' });
($iterator) = $result->iterator( [ $result->next, $result->next ] );
$iterator->add_limit(1);
ok! $iterator->is_finished ;
$wine = $iterator->next;
ok $wine, 'Found Caymus';
is $wine->name, 'Caymus';
ok ! $iterator->next; 
ok $iterator->is_finished;


# raising the limit should trigger a new search
($result) = Wine->result({}, { sort => 'name', direction => 'ascend' });
($iterator) = $result->iterator( [ $result->next, $result->next ] );
$iterator->add_limit(9999);
ok! $iterator->is_finished;
$wine = $iterator->next;
ok $wine, 'Found Caymus';
is $wine->name, 'Caymus';
ok $iterator->next, 'more to go';
ok ! $iterator->is_finished, "we're not finished";


# testing limit in args
($result) = Wine->result({}, { limit => 2, sort => 'name', direction => 'ascend' });
ok! $result->is_finished ;
$wine = $result->next;
is $wine->name, 'Caymus';
$wine = $result->next;
is $wine->name, 'Saumur Champigny, Le Grand Clos 2001';
ok ! $result->next; 
ok $result->is_finished;

# raising the limit should trigger a new search
($result) = Wine->result({}, { limit => 2, sort => 'name', direction => 'ascend' });
$result->add_limit(3);
is $result->next->name, 'Caymus';
is $result->next->name, 'Saumur Champigny, Le Grand Clos 2001';
is $result->next->name, 'Stags Leap';

# test slice again with _results_loaded
$result->rewind;
{
    my $rs = $result->slice(0, 2);
    for my $r (@$rs) {
        isa_ok $r, 'Wine';
    }

    my $objs;
    $objs = $result->slice(0, 100);
    is @$objs, 3;

    $objs = $result->slice(5, 10);
    is @$objs, 0;
}

# test add_term
{
    my $result = Wine->result({rating => { op => '<=', 'value' => 4}}, { sort => 'rating', direction => 'descend' });
    $result->add_term({rating => 3});
    is $result->next->rating, 3;
}
## now call add_term after loading objects
{
    my $result = Wine->result({rating => { op => '<=', 'value' => 4}}, { sort => 'rating', direction => 'descend' });
    $result->_load_results;
    $result->add_term({rating => 3});
    is $result->next->rating, 3;
}
## filtering with 'op', which does work if objects are not loaded
{
    my $result = Wine->result({rating => { op => '<=', 'value' => 4}}, { sort => 'rating', direction => 'descend' });
    $result->add_term({rating => { op => '<=', 'value' => 3}});
    is $result->next->rating, 3;
}
## filtering with 'op', which doesn't work now.
{
    my $result = Wine->result({rating => { op => '<=', 'value' => 4}}, { sort => 'rating', direction => 'descend' });
    $result->_load_results;
    $result->add_term({rating => { op => '<=', 'value' => 3}});
    diag "calling next() after add_term() with 'op'" . $result->next; ## this should return the object which has "rating == 3".
}

teardown_dbs(qw( global ));
