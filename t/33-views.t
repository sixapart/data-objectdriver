# $Id$

use strict;

use lib 't/lib/views';

require 't/lib/db-common.pl';

use Test::More;
BEGIN {
    unless (eval { require DBD::SQLite }) {
        plan skip_all => 'Tests require DBD::SQLite';
    }
}
plan tests => 4;

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

my %counts = map { $_->ingredient_name => $_->count } @ingredients;
is($counts{'Vanilla Ice Cream'}, 2);
is($counts{'Bananas'}, 1);
is($counts{'Chocolate Chips'}, 1);

teardown_dbs(qw( global ));
