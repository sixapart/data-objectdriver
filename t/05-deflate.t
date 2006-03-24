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

plan tests => 18;

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

## Install some deflate/inflate in the Cache driver.
{
    no warnings 'once';
    *Data::ObjectDriver::Driver::Cache::Cache::deflate = sub {
        $_[1]->deflate;
    };
    *Data::ObjectDriver::Driver::Cache::Cache::inflate = sub {
        $_[1]->inflate($_[2]);
    };
}

## Ingredients are cached, so make sure that they survive the
## deflate/inflate process.
my $ingredient = Ingredient->new;
$ingredient->recipe_id($recipe->id);
$ingredient->name('Egg');
$ingredient->quantity(5);
$ingredient->save;

my $i2 = Ingredient->lookup([ $recipe->id, $ingredient->id ]);
is $i2->id, $ingredient->id;
is $i2->recipe_id, $ingredient->recipe_id;
is $i2->name, $ingredient->name;
is $i2->quantity, $ingredient->quantity;

my $i3 = Ingredient->new;
$i3->recipe_id($recipe->id);
$i3->name('Milk');
$i3->quantity(1);
$i3->save;

my $is = Ingredient->lookup_multi([
        [ $recipe->id, $ingredient->id ],
        [ $recipe->id, $i3->id ],
    ]);
is scalar(@$is), 2;
is $is->[0]->name, 'Egg';
ok $is->[0]->{__cached};
is $is->[1]->name, 'Milk';
ok !$is->[1]->{__cached};

## Do it again! They should both be cached, now.
$is = Ingredient->lookup_multi([
        [ $recipe->id, $ingredient->id ],
        [ $recipe->id, $i3->id ],
    ]);
is scalar(@$is), 2;
is $is->[0]->name, 'Egg';
ok $is->[0]->{__cached};
is $is->[1]->name, 'Milk';
ok $is->[1]->{__cached};

teardown_dbs(qw( global ));
