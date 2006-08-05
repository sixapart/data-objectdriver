# $Id$

package Ingredient;
use strict;
use base qw( Data::ObjectDriver::BaseObject );

use Carp ();
use Cache::Memory;
use Data::ObjectDriver::Driver::Cache::Cache;
use Data::ObjectDriver::Driver::SimplePartition;

our %IDs;

__PACKAGE__->install_properties({
    columns => [ 'id', 'recipe_id', 'name', 'quantity' ],
    datasource => 'ingredients',
    primary_key => [ 'recipe_id', 'id' ],
    driver      => Data::ObjectDriver::Driver::Cache::Cache->new(
        cache => Cache::Memory->new,
        fallback => Data::ObjectDriver::Driver::SimplePartition->new(
            using           => 'Recipe',
            pk_generator    => \&generate_pk,
        ),
    ),
});

sub generate_pk {
    my($obj) = @_;
    $obj->id(++$IDs{$obj->recipe_id});
    1;
}

1;
