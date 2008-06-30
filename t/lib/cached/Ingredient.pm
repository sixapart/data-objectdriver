# $Id$

package Ingredient;
use strict;
use base qw( Data::ObjectDriver::BaseObject );

use Carp ();
use Data::ObjectDriver::Driver::DBI;
use Data::ObjectDriver::Driver::Cache::RAM;

our %IDs;

__PACKAGE__->install_properties({
    columns => [ 'id', 'recipe_id', 'name', 'quantity' ],
    datasource => 'ingredients',
    primary_key => [ 'recipe_id', 'id' ],
    driver      => Data::ObjectDriver::Driver::Cache::RAM->new(
        fallback => Data::ObjectDriver::Driver::DBI->new(
            dsn      => 'dbi:SQLite:dbname=global.db',
            pk_generator => \&generate_pk,
            reuse_dbh => 1,
        ),
        pk_generator => \&generate_pk,
    ),
});

sub generate_pk {
    my($obj) = @_;
    $obj->id(++$IDs{$obj->recipe_id});
    1;
}

1;
