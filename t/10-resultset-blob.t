# $Id: 01-col-inheritance.t 989 2005-09-23 19:58:01Z btrott $

use strict;
use warnings;

use lib 't/lib';

$Data::ObjectDriver::DEBUG = 0;
use Test::More;
use DodTestUtil;
BEGIN { eval { require Digest::SHA; 1 } or plan skip_all => 'requires Digest::SHA' }

BEGIN { DodTestUtil->check_driver }

plan tests => 5;

setup_dbs({
    global => [ qw( wines ) ],
});

use Wine;
use Storable;

my $wine = Wine->new;
$wine->name("Saumur Champigny, Le Grand Clos 2001");
$wine->rating(4);

## generate some binary data (SQL_BLOB / MEDIUMBLOB)
my $binary = Digest::SHA::sha1("binary");
$wine->content($binary);
ok($wine->save, 'Object saved successfully');

my $iter;

$iter = Data::ObjectDriver::Iterator->new(sub {});
my $wine_id = $wine->id;
undef $wine;
$wine = Wine->lookup($wine_id); 

ok $wine;
ok $wine->content eq $binary;

my @names = qw(Margaux Latour);
Wine->bulk_insert([qw(name content)], [ map {[$_, Digest::SHA::sha1($_)]} @names ]);

for my $name (@names) {
    my ($found) = Wine->search({name => $name});
    ok $found->content eq Digest::SHA::sha1($name);
}

disconnect_all($wine);
teardown_dbs(qw( global ));
