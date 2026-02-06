# $Id: 01-col-inheritance.t 989 2005-09-23 19:58:01Z btrott $

use strict;
use warnings;

use lib 't/lib';

$Data::ObjectDriver::DEBUG = 0;
use Test::More;
use DodTestUtil;
BEGIN { eval { require Crypt::URandom; 1 } or plan skip_all => 'requires Crypt::URandom' }

BEGIN { DodTestUtil->check_driver }

plan tests => 3;

setup_dbs({
    global => [ qw( wines ) ],
});

use Wine;
use Storable;

my $wine = Wine->new;
$wine->name("Saumur Champigny, Le Grand Clos 2001");
$wine->rating(4);

## generate some binary data (SQL_BLOB / MEDIUMBLOB)
my $binary = Crypt::URandom::urandom(300);
$wine->content($binary);
ok($wine->save, 'Object saved successfully');

my $iter;

$iter = Data::ObjectDriver::Iterator->new(sub {});
my $wine_id = $wine->id;
undef $wine;
$wine = Wine->lookup($wine_id); 

ok $wine;
ok $wine->content eq $binary;

# TODO: bulk_insert doesn't support blob yet. We need to change some of its API so that we can call column_def in each dbd's bulk_insert

disconnect_all($wine);
teardown_dbs(qw( global ));
