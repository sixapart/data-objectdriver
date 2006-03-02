# $Id$

package IngredientsWeighted;
use strict;
use base qw( Data::ObjectDriver::BaseView );

use Data::ObjectDriver::Driver::DBI;
use Data::ObjectDriver::SQL;

__PACKAGE__->install_properties({
    columns => [ 'ingredient_name', 'c' ],
    driver  => Data::ObjectDriver::Driver::DBI->new(
            dsn      => 'dbi:SQLite:dbname=global.db',
            pk_generator => \&generate_pk,
        ),
});

sub base_statement {
    my $class = shift;
    my $stmt = Data::ObjectDriver::SQL->new;
    $stmt->add_select('ingredients.name' => 'ingredient_name');
    $stmt->add_select('COUNT(*)' => 'c');
    $stmt->from([ 'ingredient2recipe', 'ingredients' ]);
    $stmt->add_where('ingredients.id' => \'= ingredient2recipe.ingredient_id');
    $stmt->group({ column => 'ingredient2recipe.ingredient_id' });
    $stmt;
}

1;
