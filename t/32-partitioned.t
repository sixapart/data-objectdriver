# $Id$

use strict;

use lib 't/lib/partitioned';

require 't/lib/db-common.pl';

use Test::More;
unless (eval { require DBD::SQLite }) {
    plan skip_all => 'Tests require DBD::SQLite';
}
plan tests => 92;

setup_dbs({
    global   => [ qw( recipes ) ],
    cluster1 => [ qw( ingredients ) ],
    cluster2 => [ qw( ingredients ) ],
});

use Recipe;
use Ingredient;

my($tmp, $iter);

my $recipe = Recipe->new;
$recipe->title('Banana Milkshake');
ok($recipe->save, 'Object saved successfully');
ok($recipe->recipe_id, 'Recipe has an ID');
ok($recipe->partition_id, 'Recipe assigned to a cluster');
is($recipe->title, 'Banana Milkshake', 'Title is Banana Milkshake');

$recipe->title('My Banana Milkshake');
ok($recipe->save, 'Object updated successfully');
is($recipe->title, 'My Banana Milkshake', 'Title is My Banana Milkshake');

$tmp = Recipe->lookup($recipe->recipe_id);
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
$iter->end();

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
$iter->end();

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
ok($recipe2->partition_id, 'Recipe assigned to a cluster');
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

eval {
    my @i = Ingredient->search({ name => 'Chocolate Chips' });
}; ok ($@);
like $@, qr/Cannot extract/;
my @i = Ingredient->search({ name => 'Chocolate Chips' }, { multi_partition => 1 });
is @i, 1;
is $i[0]->name, 'Chocolate Chips';

is $ingredient->remove, 1, 'Ingredient removed successfully';
is $ingredient2->remove, 1, 'Ingredient removed successfully';
is $ingredient3->remove, 1, 'Ingredient removed successfully';
is $recipe->remove, 1, 'Recipe removed successfully';
is $recipe2->remove, 1, 'Recipe removed successfully';

require 't/txn-common.pl';

sub DESTROY { teardown_dbs(qw( global cluster1 cluster2 )); }
