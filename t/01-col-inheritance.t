# $Id$

use strict;

use lib 't/lib';

require 't/lib/db-common.pl';

use Test::More;
unless (eval { require DBD::SQLite }) {
    plan skip_all => 'Tests require DBD::SQLite';
}
plan tests => 15;

setup_dbs({
    global => [ qw( wines ) ],
});

use Wine;

my $wine = Wine->new;
my %expected = map { $_ => 1 } qw(name rating id cluster_id content binchar); 
my %data;
# I know about Test::Deep. Do not ask...
for my $col (@{ $wine->column_names }) {
    $data{$col}++;
    ok $expected{$col}, "$col was expected";
}
for my $col (keys %expected) {
    ok $data{$col}, "expected $col is present"; 
}
$wine->name("Saumur Champigny, Le Grand Clos 2001");
$wine->rating(4);
ok($wine->save, 'Object saved successfully');

ok ($wine->has_column("id")) ;
ok ($wine->has_column("rating")) ;

sub DESTROY { teardown_dbs(qw( global )); }
