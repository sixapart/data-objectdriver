# $Id$

use strict;
use warnings;

use lib 't/lib';
use lib 't/lib/views';

use Test::More;
use DodTestUtil;
BEGIN { DodTestUtil->check_driver }

plan tests => 6;

setup_dbs({
    global   => [ qw( recipes ingredients-view ingredient2recipe ) ],
});

use Recipe;
use Ingredient;
use IngredientsWeighted;

my($tmp, $iter);

my $milkshake = Recipe->new;
$milkshake->title('Banana Milkshake');
$milkshake->save;

my $ice_cream = $milkshake->add_ingredient_by_name('Vanilla Ice Cream', 1);
my $banana = $milkshake->add_ingredient_by_name('Bananas', 5);

my $cookies = Recipe->new;
$cookies->title('Chocolate Chip Cookies');
$cookies->save;

my $chip = $cookies->add_ingredient_by_name('Chocolate Chips', 100);
$cookies->add_ingredient($ice_cream);

my @ingredients = IngredientsWeighted->search;
is(scalar(@ingredients), 3);

my %counts = map { $_->ingredient_name => $_->c } @ingredients;
is($counts{'Vanilla Ice Cream'}, 2);
is($counts{'Bananas'}, 1);
is($counts{'Chocolate Chips'}, 1);

@ingredients = IngredientsWeighted->search(
    { c => { op => '<', value => 2 } },
);

SKIP: {
    skip "DBD::SQLite bug?", 2;
    is @ingredients, 1;
    is $ingredients[0]->name, 'Vanilla Ice Cream';
}

END {
    disconnect_all(qw/Recipe Ingredient Ingredient2Recipe IngredientsWeighted/);
    teardown_dbs(qw( global ));
}
