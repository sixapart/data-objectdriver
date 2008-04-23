# $Id: 01-col-inheritance.t 989 2005-09-23 19:58:01Z btrott $

# this is about the same test as t/09-resultset.t, but with lots of peek_next'ing 
# going on, to test that new method

use strict;

use lib 't/lib';

require 't/lib/db-common.pl';

$Data::ObjectDriver::DEBUG = 0;
use Test::More;
unless (eval { require DBD::SQLite }) {
    plan skip_all => 'Tests require DBD::SQLite';
}
plan tests => 65;

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

$wine = undef;
my ($result) = Wine->result({name => 'Caymus'});
is $result->peek_next->name, 'Caymus', 'before we start, peek_next says the first one is Caymus';
ok! $result->is_finished;
$wine = $result->next;
ok $wine, 'Found Caymus';
is $wine->name, 'Caymus';
ok ! $result->peek_next, "we're at the end of the set";
ok ! $result->next; #sets is_finished()
ok ! $result->peek_next, "we're *still* at the end of the set";
ok $result->is_finished;

# testing iterator
my ($iterator) = $result->iterator([$wine]);
is $iterator->peek_next->name, 'Caymus', 'before we start, peek_next says the first one is Caymus';
ok(! $iterator->is_finished );
$wine = $iterator->next;
ok $wine, 'Found Caymus';
is $wine->name, 'Caymus';
ok ! $iterator->peek_next, "we're at the end of the set";
ok( ! $iterator->next ); 
ok ! $iterator->peek_next, "we're *still* at the end of the set";
ok( $iterator->is_finished );

# testing bug in iterator, adding a limit where there was one before shouldn't invalidate results
($iterator) = $result->iterator([$wine]);
is $iterator->peek_next->name, 'Caymus', 'before we start, peek_next says the first one is Caymus';
$iterator->add_limit(1);
is $iterator->peek_next->name, 'Caymus', 'after adding limit, peek_next says the first one is Caymus';
ok(! $iterator->is_finished );
$wine = $iterator->next;
ok $wine, 'Found Caymus';
is $wine->name, 'Caymus';
ok ! $iterator->peek_next, "we're at the end of the set";
ok ! $iterator->next; 
ok ! $iterator->peek_next, "we're *still* at the end of the set";
ok $iterator->is_finished;


($result) = Wine->result({}, { sort => 'name', direction => 'ascend' });
($iterator) = $result->iterator( [ $result->next, $result->next ] );
is $iterator->peek_next->name, 'Caymus', 'before we start, peek_next says the first one is Caymus';
$iterator->add_limit(1);
is $iterator->peek_next->name, 'Caymus', 'after adding limit, peek_next says the first one is Caymus';
ok! $iterator->is_finished ;
$wine = $iterator->next;
ok $wine, 'Found Caymus';
is $wine->name, 'Caymus';
ok ! $iterator->peek_next, "we're at the end of the set";
ok ! $iterator->next; 
ok ! $iterator->peek_next, "we're *still* at the end of the set";
ok $iterator->is_finished;


# raising the limit should trigger a new search
($result) = Wine->result({}, { sort => 'name', direction => 'ascend' });
($iterator) = $result->iterator( [ $result->next, $result->next ] );
is $iterator->peek_next->name, 'Caymus', 'before we start, peek_next says the first one is Caymus';
$iterator->add_limit(9999);
is $iterator->peek_next->name, 'Caymus', 'after adding limit, peek_next says the first one is Caymus';
ok! $iterator->is_finished;
$wine = $iterator->next;
ok $wine, 'Found Caymus';
is $wine->name, 'Caymus';
ok $iterator->peek_next, "more to go";
ok $iterator->next, 'more to go';
ok ! $iterator->peek_next, "that was the last one, there are no more";
ok ! $iterator->is_finished, "we're not finished";
ok ! $iterator->next; #sets is_finished()
ok ! $iterator->peek_next, "that was the last one, there are no more";
ok $iterator->is_finished, "now we are finished";


# testing limit in args
($result) = Wine->result({}, { limit => 2, sort => 'name', direction => 'ascend' });
is $result->peek_next->name, 'Caymus', 'before we start, peek_next says the first one is Caymus';
ok! $result->is_finished ;
$wine = $result->next;
is $wine->name, 'Caymus';
is $result->peek_next->name, 'Saumur Champigny, Le Grand Clos 2001', 'the next one will be Saumur';
$wine = $result->next;
is $wine->name, 'Saumur Champigny, Le Grand Clos 2001';
ok ! $result->peek_next, "Saumur was the last one";
ok ! $result->next; 
ok $result->is_finished;
ok ! $result->peek_next, "Saumur was really the last one";

# raising the limit should trigger a new search
($result) = Wine->result({}, { limit => 2, sort => 'name', direction => 'ascend' });
$result->add_limit(3);
is $result->next->name, 'Caymus';
is $result->peek_next->name, 'Saumur Champigny, Le Grand Clos 2001', 'the next one will be Saumur';
is $result->next->name, 'Saumur Champigny, Le Grand Clos 2001';
is $result->peek_next->name, 'Stags Leap', 'the next one will be Stags Leap';
is $result->next->name, 'Stags Leap';
ok ! $result->peek_next, "Stags Leap was the last one";

teardown_dbs(qw( global ));
