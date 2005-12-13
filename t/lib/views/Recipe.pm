# $Id$

package Recipe;
use strict;
use base qw( Data::ObjectDriver::BaseObject );

use Data::ObjectDriver::Driver::DBI;
use Ingredient;
use Ingredient2Recipe;

__PACKAGE__->install_properties({
    columns => [ 'id', 'title' ],
    datasource => 'recipes',
    primary_key => 'id',
    driver => Data::ObjectDriver::Driver::DBI->new(
        dsn      => 'dbi:SQLite:dbname=global.db',
    ),
});

sub add_ingredient_by_name {
    my $recipe = shift;
    my($name, $quantity) = @_;

    my $ingredient = Ingredient->new;
    $ingredient->name($name);
    $ingredient->quantity($quantity);
    $ingredient->save;

    $recipe->add_ingredient($ingredient);

    $ingredient;
}

sub add_ingredient {
    my $recipe = shift;
    my($ingredient) = @_;
    my $map = Ingredient2Recipe->new;
    $map->ingredient_id($ingredient->id);
    $map->recipe_id($recipe->id);
    $map->save;
}

1;
