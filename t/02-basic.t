# $Id: 01-col-inheritance.t 989 2005-09-23 19:58:01Z btrott $

use strict;

use lib 't/lib';

require 't/lib/db-common.pl';

use Test::More;
unless (eval { require DBD::SQLite }) {
    plan skip_all => 'Tests require DBD::SQLite';
}
plan tests => 3;

use Wine;

setup_dbs({
    global => [ qw( wines ) ],
});

# refresh
{ 
    my $old ='Cul de Veau à la Sauge'; # tastes good !
    my $new ='At first my tests ran on Recipe, sorry (Yann)';
    my $w1 = Wine->new;
    $w1->name($old);
    $w1->save;
    my $id = $w1->id;
    
    my $w2 = Wine->lookup($id);
    $w2->name($new);
    $w2->save;
    cmp_ok $w1->name, 'eq', $old, "Old name not updated...";
    cmp_ok $w2->name, 'eq', $new, "... but new name is set";

    $w1->refresh;

    cmp_ok $w1->name, 'eq', $new, "Refreshed";
}
teardown_dbs(qw( global ));

