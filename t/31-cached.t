# $Id$

use strict;

use lib 't/lib';  # for Cache::Memory substitute.
use lib 't/lib/cached';

require 't/lib/db-common.pl';

use Test::More;
BEGIN {
    unless (eval { require DBD::SQLite }) {
        plan skip_all => 'Tests require DBD::SQLite';
    }
    unless (eval { require Cache::Memory }) {
        plan skip_all => 'Tests require Cache::Memory';
    }
}
plan tests => 104;

setup_dbs({
    global   => [ qw( recipes ingredients ) ],
});

use Recipe;
use Ingredient;

my($tmp, $iter);

my $recipe = Recipe->new;
$recipe->title('Banana Milkshake');
ok($recipe->save, 'Object saved successfully');
ok($recipe->recipe_id, 'Recipe has an ID');
is($recipe->title, 'Banana Milkshake', 'Title is Banana Milkshake');

$recipe->title('My Banana Milkshake');
ok($recipe->save, 'Object updated successfully');
is($recipe->title, 'My Banana Milkshake', 'Title is My Banana Milkshake');

$tmp = Recipe->lookup($recipe->recipe_id);
is(ref $tmp, 'Recipe', 'lookup gave us a recipe');
is($tmp->title, 'My Banana Milkshake', 'Title is My Banana Milkshake');
## same with a hash lookup
$tmp = Recipe->lookup({ recipe_id => $recipe->recipe_id });
is(ref $tmp, 'Recipe', 'lookup gave us a recipe');
is($tmp->title, 'My Banana Milkshake', 'Title is My Banana Milkshake');

my @recipes = Recipe->search;
is(scalar @recipes, 1, 'Got one recipe back from search');
is($recipes[0]->title, 'My Banana Milkshake', 'Title is My Banana Milkshake');

$iter = Recipe->search;
ok($iter, 'Got an iterator object');
$tmp = $iter->();
ok(!$iter->(), 'Iterator gave us only one recipe');
is(ref $tmp, 'Recipe', 'Iterator gave us a recipe');
is($tmp->title, 'My Banana Milkshake', 'Title is My Banana Milkshake');

my $ingredient = Ingredient->new;
$ingredient->recipe_id($recipe->recipe_id);
$ingredient->name('Vanilla Ice Cream');
$ingredient->quantity(1);
ok($ingredient->save, 'Ingredient saved successfully');
ok($ingredient->id, 'Ingredient has an ID');
is($ingredient->id, 1, 'ID is 1');
is($ingredient->name, 'Vanilla Ice Cream', 'Name is Vanilla Ice Cream');

$tmp = Ingredient->lookup([ $recipe->recipe_id, $ingredient->id ]);
is(ref $tmp, 'Ingredient', 'lookup gave us an ingredient');
is($tmp->name, 'Vanilla Ice Cream', 'Name is Vanilla Ice Cream');

my @ingredients = Ingredient->search({ recipe_id => $recipe->recipe_id });
is(scalar @ingredients, 1, 'Got one ingredient back from search');
is($ingredients[0]->name, 'Vanilla Ice Cream', 'Name is Vanilla Ice Cream');

$iter = Ingredient->search({ recipe_id => $recipe->recipe_id });
ok($iter, 'Got an iterator object');
$tmp = $iter->();
ok(!$iter->(), 'Iterator gave us only one ingredient');
is(ref $tmp, 'Ingredient', 'Iterator gave us an ingredient');
is($tmp->name, 'Vanilla Ice Cream', 'Name is Vanilla Ice Cream');

my $ingredient2 = Ingredient->new;
$ingredient2->recipe_id($recipe->recipe_id);
$ingredient2->name('Bananas');
$ingredient2->quantity(5);
ok($ingredient2->save, 'Ingredient saved successfully');
ok($ingredient2->id, 'Ingredient has an ID');
is($ingredient2->id, 2, 'ID is 2');
is($ingredient2->name, 'Bananas', 'Name is Bananas');

@ingredients = Ingredient->search({ recipe_id => $recipe->recipe_id, quantity => 5 });
is(scalar @ingredients, 1, 'Got one ingredient back from search');
is($ingredients[0]->id, $ingredient2->id, 'ID is for the Bananas object');
is($ingredients[0]->name, 'Bananas', 'Name is Bananas');

my $recipe2 = Recipe->new;
$recipe2->title('Chocolate Chip Cookies');
ok($recipe2->save, 'Object saved successfully');
ok($recipe2->recipe_id, 'Recipe has an ID');
is($recipe2->title, 'Chocolate Chip Cookies', 'Title is Chocolate Chip Cookies');

my $ingredient3 = Ingredient->new;
$ingredient3->recipe_id($recipe2->recipe_id);
$ingredient3->name('Chocolate Chips');
$ingredient3->quantity(100);
ok($ingredient3->save, 'Ingredient saved successfully');
ok($ingredient3->id, 'Ingredient has an ID');
is($ingredient3->id, 1, 'ID is 1');
is($ingredient3->name, 'Chocolate Chips', 'Name is Chocolate Chips');

$tmp = Ingredient->lookup([ $recipe2->recipe_id, 1 ]);
is(ref $tmp, 'Ingredient', 'lookup gave us an ingredient');
is($tmp->name, 'Chocolate Chips', 'Name is Chocolate Chips');

$tmp = Ingredient->lookup([ $recipe2->recipe_id, 1 ]);
is(ref $tmp, 'Ingredient', 'lookup again (for caching)');
is($tmp->name, 'Chocolate Chips', 'Name is Chocolate Chips');

my $all = Ingredient->lookup_multi([
        [ $recipe->recipe_id, 1 ],
        [ $recipe->recipe_id, 2 ],
        [ $recipe2->recipe_id, 1 ],
]);
is(scalar @$all, 3, 'Got back 3 ingredients from lookup_multi');
is($all->[0]->name, 'Vanilla Ice Cream', 'lookup_multi results in right order');
is($all->[1]->name, 'Bananas', 'lookup_multi results in right order');
is($all->[2]->name, 'Chocolate Chips', 'lookup_multi results in right order');

## lookup_multi using hashes (Same test than above)
$all = Ingredient->lookup_multi([
    { recipe_id => $recipe->recipe_id, id => 1 },
    { recipe_id => $recipe->recipe_id, id => 2 },
    { recipe_id => $recipe2->recipe_id, id => 1 },
]);
is(scalar @$all, 3, 'Got back 3 ingredients from lookup_multi');
is($all->[0]->name, 'Vanilla Ice Cream', 'lookup_multi results in right order');
is($all->[1]->name, 'Bananas', 'lookup_multi results in right order');
is($all->[2]->name, 'Chocolate Chips', 'lookup_multi results in right order');

# fetch_data tests
my $data = $recipe->fetch_data;
is_deeply 
    $data, { title => "My Banana Milkshake", recipe_id => 1 },
    "(DBI) fetch_data - recipe not cached";

$data = $ingredient->fetch_data;
is_deeply $data,
    { name => "Vanilla Ice Cream", quantity => 1, recipe_id => 1, id => 1 },
    "(Cache) fetch_data - ingredient is cached";

is($ingredient->remove, 1, 'Ingredient removed successfully');
is($ingredient2->remove, 1, 'Ingredient removed successfully');

## demonstration that we have a problem with caching and transaction
{
    # ingredient3 should already be hot in the cache anyway
    Data::ObjectDriver::BaseObject->begin_work;
    $ingredient3->quantity(300); # originally was 100
    $ingredient3->save;
    
    my $same = Ingredient->lookup($ingredient3->primary_key);
    is $same->quantity, 300;
    
    Data::ObjectDriver::BaseObject->rollback;

    $same = Ingredient->lookup($ingredient3->primary_key);
    is $same->quantity, 100;
}

# let's remove ingredient3 with Class methods
eval {
    Ingredient->remove({ name => 'Chocolate Chips' }, { nofetch => 1 });
}; 
ok($@, "nofetch option will make the driver dies if cache is involved");

is(Ingredient->remove({ name => 'Chocolate Chips' }), 1, "Removed with class method");
ok(! Ingredient->lookup(1), "really deleted");

is($recipe->remove, 1, 'Recipe removed successfully');
is($recipe2->remove, 1, 'Recipe removed successfully');

require 't/txn-common.pl';

sub DESTROY { teardown_dbs(qw( global )); }
