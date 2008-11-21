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

plan tests => 90;

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
    no warnings 'redefine';
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
is $deflated->{columns}{recipe_id}, $recipe->recipe_id;
is $deflated->{columns}{title}, $recipe->title;

isa_ok $deflated->{ingredients}, 'ARRAY';
is scalar(@{ $deflated->{ingredients} }), 0;

my $ingredient = Ingredient->new;
$ingredient->recipe_id($recipe->recipe_id);
$ingredient->name('Egg');
$ingredient->quantity(5);
$ingredient->save;
delete $recipe->{__ingredients};

$deflated = $recipe->deflate;
isa_ok $deflated->{ingredients}, 'ARRAY';
is scalar(@{ $deflated->{ingredients} }), 1;

my $r2 = Recipe->inflate($deflated);
is $r2->recipe_id, $recipe->recipe_id;
is $r2->title, $recipe->title;

## Inspect the internal array, since it should have been populated
## by inflate.
my $ingredients = $r2->{__ingredients};
isa_ok $ingredients, 'ARRAY';
is scalar(@$ingredients), 1;
isa_ok $ingredients->[0], 'Ingredient';
is $ingredients->[0]->id, $ingredient->id;
is $ingredients->[0]->recipe_id, $ingredient->recipe_id;
is $ingredients->[0]->name, $ingredient->name;
is $ingredients->[0]->quantity, $ingredient->quantity;

my $i2 = Ingredient->new;
$i2->recipe_id($recipe->recipe_id);
$i2->name('Egg');
$i2->quantity(5);
$i2->save;

my $is = Ingredient->lookup_multi([
        [ $recipe->recipe_id, $ingredient->id ],
        [ $recipe->recipe_id, $i2->id ],
    ]);
is scalar(@$is), 2;
ok $is->[0]{__cached};
ok !$is->[1]{__cached};

$is = Ingredient->lookup_multi([
        [ $recipe->recipe_id, $ingredient->id ],
        [ $recipe->recipe_id, $i2->id ],
    ]);
is scalar(@$is), 2;
ok $is->[0]{__cached};
ok $is->[1]{__cached};

my $i3 = Ingredient->new;
$i3->recipe_id($recipe->recipe_id);
$i3->name('Flour');
$i3->quantity(10);
$i3->save;

## Try loading with fetchonly first. The driver shouldn't cache the results.
my @is = Ingredient->search({ recipe_id => $recipe->recipe_id }, { fetchonly => [ 'recipe_id', 'id' ] });
is scalar(@is), 3;

## Flour should not yet be cached.
my $i4 = Ingredient->lookup([ $recipe->recipe_id, $i3->id ]);
ok !$i4->{__cached};
is $i4->name, 'Flour';

## verify it's in the cache
my $key = $i4->driver->cache_key(ref($i4), $i4->primary_key);
my $data = $i4->driver->get_from_cache($key);
ok $data;
is $data->{columns}{id}, $i3->id, "it's in the cache";
## Delete it from the cache, so that the next test is actually accurate.
$i4->uncache_object;
ok ! $i4->driver->get_from_cache($key), "It's been purged from the cache";

## Now look up the ingredients again. Milk and Eggs should already be cached,
## and doing the search should now cache Flour.
@is = Ingredient->search({ recipe_id => $recipe->recipe_id });
is scalar(@is), 3;

## this is still working if we add a comment 
@is = Ingredient->search({ recipe_id => $recipe->recipe_id }, { comment => "mytest" });
is scalar(@is), 3;

## Flour should now be cached.
$i4 = Ingredient->lookup([ $recipe->recipe_id, $i3->id ]);
ok $i4->{__cached};
is $i4->name, 'Flour';

## Now look up the recipe, so that we make sure it gets cached...
my $r3 = Recipe->lookup($recipe->recipe_id);
ok !$r3->{__cached};
is $r3->recipe_id, $recipe->recipe_id;
is $r3->title, $recipe->title;

## Now look it up again. We should get the cached version, and it
## should get inflated.
$r3 = Recipe->lookup($recipe->recipe_id);
ok $r3->{__cached};
is $r3->recipe_id, $recipe->recipe_id;
is $r3->title, $recipe->title;
$ingredients = $r3->{__ingredients};
isa_ok $ingredients, 'ARRAY';
is scalar(@$ingredients), 3;
isa_ok $ingredients->[0], 'Ingredient';
is $ingredients->[0]->id, $ingredient->id;
is $ingredients->[0]->recipe_id, $ingredient->recipe_id;
is $ingredients->[0]->name, $ingredient->name;
is $ingredients->[0]->quantity, $ingredient->quantity;

## Now add a cache_version to Recipe dynamically, so that the cache_key
## changes the next time we try to do a lookup.
*Recipe::cache_version = *Recipe::cache_version = sub { '1.0' };
$r3 = Recipe->lookup($recipe->recipe_id);
ok !$r3->{__cached};

$r3 = Recipe->lookup($recipe->recipe_id);
ok $r3->{__cached};

## test replace 
my $to_replace = Recipe->new;
$to_replace->title('Cake');
$to_replace->replace;
ok (my $rid = $to_replace->recipe_id);

my $replaced = Recipe->lookup($rid);
ok ! $replaced->{__cached};

$to_replace = Recipe->new;
$to_replace->recipe_id($rid);
$to_replace->title('Cup Cake');
$to_replace->replace;

$replaced = Recipe->lookup($rid);
ok $replaced->{__cached};
is $replaced->title, 'Cup Cake';

require 't/txn-common.pl';

sub DESTROY { teardown_dbs(qw( global cluster1 cluster2 )); }
