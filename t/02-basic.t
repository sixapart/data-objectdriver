# $Id: 01-col-inheritance.t 989 2005-09-23 19:58:01Z btrott $

use strict;

use lib 't/lib';
use lib 't/lib/cached';

require 't/lib/db-common.pl';

use Test::More;
use Test::Exception;
BEGIN {
    unless (eval { require DBD::SQLite }) {
        plan skip_all => 'Tests require DBD::SQLite';
    }
    unless (eval { require Cache::Memory }) {
        plan skip_all => 'Tests require Cache::Memory';
    }
}

plan tests => 23;

use Wine;
use Recipe;
use Ingredient;

setup_dbs({
    global => [ qw( wines recipes ingredients) ],
});

# method installation
{ 
    my $w = Wine->new;
    ok $w->name("name");
    ok $w->has_column("name");
    ok ! $w->has_column("inexistent");
    dies_ok { $w->inexistent("hell") } "dies on setting inexistent column : 'inexistent()'";
    dies_ok { $w->column('inexistent') } "dies on setting inexistent column : 'column()'";
}

# refresh
{ 
    my $old ='Cul de Veau à la Sauge'; # tastes good !
    my $new ='At first my tests ran on Recipe, sorry (Yann)';
    my $w1 = Wine->new;
    $w1->name($old);
    ok $w1->save;
    my $id = $w1->id;
    
    my $w2 = Wine->lookup($id);
    $w2->name($new);
    $w2->save;
    cmp_ok $w1->name, 'eq', $old, "Old name not updated...";
    cmp_ok $w2->name, 'eq', $new, "... but new name is set";

    $w1->refresh;

    cmp_ok $w1->name, 'eq', $new, "Refreshed";
    ok $w1->remove;
    ok $w2->remove;
}

# lookup with hash (single pk) 
{
    my $w = Wine->new;
    $w->name("Veuve Cliquot");
    $w->save;
    my $id = $w->id;
    undef $w;

    # lookup test
    lives_ok { $w = Wine->lookup({ id => $id })} "Alive !";
    cmp_ok $w->name, 'eq', 'Veuve Cliquot', "simple data test";

    ok $w;
    ok $w->remove;
}

# lookup with hash (multiple pk) 
{
    my $r = Recipe->new;
    $r->title("Good one");
    ok $r->save;
    my $rid = $r->id;
    ok $rid;

    my $i = Ingredient->new;
    $i->recipe_id($rid);
    $i->quantity(1);
    $i->name('Chouchenn');
    ok $i->save;
    my $id = $i->id;
    undef $i;
    
    # lookup test
    dies_ok  { $i = Ingredient->lookup({ id => $id, quantity => 1 })} "Use Search !";
    lives_ok { $i = Ingredient->lookup({ id => $id, recipe_id => $rid })} "Alive";
    cmp_ok $i->name, 'eq', 'Chouchenn', "simple data test";

    ok $r->remove;
    ok $i->remove;
}

teardown_dbs(qw( global ));

