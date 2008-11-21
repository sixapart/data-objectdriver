# $Id$

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

plan tests => 21;

use Wine;
use Recipe;
use Ingredient;
use PkLess; 

setup_dbs({
    global => [ qw( wines recipes ingredients pkless) ],
});

## TODO: test primary_key

# test correct behaviour of has_primary_key
{
    my $w = Wine->new;
    $w->save;
    ok $w->has_primary_key, "wine has pk";

    my $r = Recipe->new;
    $r->save;
    ok $r->has_primary_key, "recipe has pk";;
    
    my $i = Ingredient->new;
    $i->recipe_id($r->recipe_id);
    $i->save;
    ok $i->has_primary_key, "ingredient has (multi) pk";

    ## PK less
    my $p = PkLess->new;
    $p->anything("x");
    $p->save;
    ok ! $p->has_primary_key, "pkless has no pk";;

    my $p2 = PkLess->new;
    $p2->anything("y");
    $p2->save;

    ## save behaves correctly (there's never an UPDATE)
    my @res = PkLess->search();
    is scalar @res, 2, "Pk-less populated correctly";
}

# simple class pk fields
{
    isa_ok(Wine->primary_key_tuple(), 'ARRAY', q(Wine's primary key tuple is an arrayref));
    is_deeply(Wine->primary_key_tuple(), ['id'], q(Wine's primary key tuple contains the string 'id'));
    is_deeply(Wine->primary_key_to_terms([100]), { id => 100 });
}

# complex class pk fields
{
    isa_ok(Ingredient->primary_key_tuple, 'ARRAY', q(Ingredient's primary key tuple is an arrayref));
    is_deeply(Ingredient->primary_key_tuple, ['recipe_id', 'id'], q(Ingredient instance's primary key tuple contains 'recipe_id' and 'id'));
    is_deeply(Ingredient->primary_key_to_terms([100, 1000]), { recipe_id => 100, id => 1000 });
}

# simple instance pk fields
{
    my $w = Wine->new;
    isa_ok $w->primary_key_tuple, 'ARRAY', q(Wine instance's primary key tuple is an arrayref);
    is_deeply $w->primary_key_tuple, ['id'], q(Wine instance's primary key tuple contains the string 'id');
    is_deeply($w->primary_key_to_terms, { id => $w->id });
}

# complex instance pk fields
{
    my $i = Ingredient->new;
    is ref $i->primary_key_tuple, 'ARRAY', q(Ingredient instance's primary key tuple is an arrayref);
    is_deeply $i->primary_key_tuple, ['recipe_id', 'id'], q(Ingredient instance's primary key tuple contains 'recipe_id' and 'id');
    is_deeply($i->primary_key_to_terms, { recipe_id => $i->recipe_id, id => $i->id });
}

# 0 might be a valid pk
{ 
    my $rv = Wine->remove({});
    # make sure that remove returns the number of records deleted (1)
    is($rv, 1, 'correct number of rows deleted');

    my $wine = Wine->new;
    $wine->id(0);
    $wine->name("zero");
    ok $wine->save;
    $wine = Wine->lookup(0);
    ok $wine;
    is $wine->name, "zero";
}

sub DESTROY { teardown_dbs(qw( global )); }

