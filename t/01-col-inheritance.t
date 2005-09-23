# $Id$

use strict;

use lib 't/lib';

require 't/lib/db-common.pl';

setup_dbs({
    global => [ qw( wines ) ],
});

use Wine;
use Test::More tests => 11;

my $wine = Wine->new;
my %expected = ( name => 1, rating => 1, id => 1, cluster_id => 1 ); 
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

teardown_dbs(qw( global ));
