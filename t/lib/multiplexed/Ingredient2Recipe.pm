# $Id$

package Ingredient2Recipe;
use strict;
use base qw( Data::ObjectDriver::BaseObject );

use Data::ObjectDriver::Driver::DBI;
use Data::ObjectDriver::Driver::Multiplexer;

my $global1_driver = Data::ObjectDriver::Driver::DBI->new(
    dsn => 'dbi:SQLite:dbname=global1.db',
);

my $global2_driver = Data::ObjectDriver::Driver::DBI->new(
    dsn => 'dbi:SQLite:dbname=global2.db',
);

__PACKAGE__->install_properties({
    columns     => [ 'recipe_id', 'ingredient_id', "value1" ],
    datasource  => 'ingredient2recipe',
    primary_key => 'recipe_id', ## should match lookup XXX could we auto generate it ? 
    driver      => Data::ObjectDriver::Driver::Multiplexer->new(

        ## Send searches by recipe_id to $global1_driver, and
        ## searches by ingredient_id to $global2_driver.
        on_search => {
            recipe_id       => $global1_driver,
            ingredient_id   => $global2_driver,
        },
        on_lookup => $global1_driver,

        drivers => [ $global1_driver, $global2_driver ],
    ),
});

1;
