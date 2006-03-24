# $Id$

use strict;

use lib 't/lib';
use lib 't/lib/both';

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

use Recipe;
use Ingredient;

setup_dbs({
    global   => [ qw( recipes ) ],
    cluster1 => [ qw( ingredients) ],
    cluster2 => [ qw( ingredients) ],
});

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

my $recipe = Recipe->new;
$recipe->title('Cake');
$recipe->save;

my $deflated = $recipe->deflate;
is $deflated->{columns}{id}, $recipe->id;
is $deflated->{columns}{title}, $recipe->title;

isa_ok $deflated->{ingredients}, 'ARRAY';
is scalar(@{ $deflated->{ingredients} }), 0;

my $ingredient = Ingredient->new;
$ingredient->recipe_id($recipe->id);
$ingredient->name('Egg');
$ingredient->quantity(5);
$ingredient->save;
delete $recipe->{__ingredients};

$deflated = $recipe->deflate;
isa_ok $deflated->{ingredients}, 'ARRAY';
is scalar(@{ $deflated->{ingredients} }), 1;

my $r2 = Recipe->inflate($deflated);
is $r2->id, $recipe->id;
is $r2->title, $recipe->title;

## Inspect the internal array, since it should have been populated
## by inflate.
my $ingredients = $r2->{__ingredients};
isa_ok $ingredients, 'ARRAY';
isa_ok $ingredients->[0], 'Ingredient';
is $ingredients->[0]->id, $ingredient->id;
is $ingredients->[0]->recipe_id, $ingredient->recipe_id;
is $ingredients->[0]->name, $ingredient->name;
is $ingredients->[0]->quantity, $ingredient->quantity;

my $i2 = Ingredient->new;
$i2->recipe_id($recipe->id);
$i2->name('Egg');
$i2->quantity(5);
$i2->save;

my $is = Ingredient->lookup_multi([
        [ $recipe->id, $ingredient->id ],
        [ $recipe->id, $i2->id ],
    ]);
is scalar(@$is), 2;
ok $is->[0]{__cached};
ok !$is->[1]{__cached};

$is = Ingredient->lookup_multi([
        [ $recipe->id, $ingredient->id ],
        [ $recipe->id, $i2->id ],
    ]);
is scalar(@$is), 2;
ok $is->[0]{__cached};
ok $is->[1]{__cached};

my $i3 = Ingredient->new;
$i3->recipe_id($recipe->id);
$i3->name('Flour');
$i3->quantity(10);
$i3->save;

my @is = Ingredient->search({ recipe_id => $recipe->id });
is scalar(@is), 3;

## Flour should now be cached.
my $i4 = Ingredient->lookup([ $recipe->id, $i3->id ]);
ok $i4->{__cached};
is $i4->name, 'Flour';

teardown_dbs(qw( global cluster1 cluster2 ));
