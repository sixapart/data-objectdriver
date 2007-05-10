# $Id: 05-deflate.t 1170 2006-03-24 05:29:48Z btrott $

use strict;

use lib 't/lib';
use lib 't/lib/cached';

require 't/lib/db-common.pl';

use Test::More;
use Test::Exception;
use Scalar::Util;
BEGIN {
    unless (eval { require DBD::SQLite }) {
        plan skip_all => 'Tests require DBD::SQLite';
    }
    unless (eval { require Cache::Memory }) {
        plan skip_all => 'Tests require Cache::Memory';
    }
    unless (eval 'use Scalar::Util qw(weaken); 1') {
        plan skip_all => 'Tests require weakref';
    }
}

plan tests => 3;

use Recipe;
use Ingredient;

setup_dbs({
    global => [ qw( recipes ingredients) ],
});

Ingredient->has_a( {
        class  => 'Recipe',
        column => 'recipe_id',
        parent_method => 'ingredients',
        method => 'recipe',
        cached => 1,
    },
);

## setup  a few datas
my $recipe = Recipe->new;
$recipe->title('Cake');
$recipe->save;

my $ingredient = Ingredient->new;
$ingredient->recipe_id($recipe->recipe_id);
$ingredient->name('Egg');
$ingredient->quantity(5);
$ingredient->save;

my $i3 = Ingredient->new;
$i3->recipe_id($recipe->recipe_id);
$i3->name('Milk');
$i3->quantity(1);
$i3->save;

{ 
    my $r = $ingredient->recipe;
    is $r->recipe_id, $recipe->recipe_id, "recipe id back using 'parent_method'";
    
    ## show me what you have in your belly.
    ok Scalar::Util::isweak($ingredient->{__cache_recipe}), "weak ref";
}

is $ingredient->{__cache_recipe}, undef, "cache has effectively been destroyed";

teardown_dbs(qw( global ));
