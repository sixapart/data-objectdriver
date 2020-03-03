# $Id$

package Ingredient2Recipe;
use strict;
use base qw( Data::ObjectDriver::BaseObject );
use DodTestUtil;

use Data::ObjectDriver::Driver::DBI;

__PACKAGE__->install_properties({
    columns => [ 'recipe_id', 'ingredient_id' ],
    datasource => 'ingredient2recipe',
    primary_key => [ 'recipe_id', 'ingredient_id', ],
    driver      => Data::ObjectDriver::Driver::DBI->new(
            dsn      => DodTestUtil::dsn('global'),
    ),
});

1;
