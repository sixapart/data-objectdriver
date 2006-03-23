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

plan tests => 4;

use Recipe;
use Ingredient;

setup_dbs({
    global => [ qw( recipes ingredients) ],
});

my $recipe = Recipe->new;
$recipe->title('Cake');
$recipe->save;

my $deflated = $recipe->deflate;
is $deflated->{columns}{id}, $recipe->id;
is $deflated->{columns}{title}, $recipe->title;

my $r2 = Recipe->inflate($deflated);
is $r2->id, $recipe->id;
is $r2->title, $recipe->title;

## Ingredients are cached, so make sure that they survive the
## deflate/inflate process.
my $ingredient = Ingredient->new;
$ingredient->recipe_id($recipe->id);
$ingredient->name('Egg');
$ingredient->quantity(5);
$ingredient->save;

teardown_dbs(qw( global ));
