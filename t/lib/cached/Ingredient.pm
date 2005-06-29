# $Id$

package Ingredient;
use strict;
use base qw( Data::ObjectDriver::BaseObject );

use Carp ();
use Data::ObjectDriver::Driver::DBI;
use Data::ObjectDriver::Driver::Cache::Memcached;
use Cache::Memcached;

our %IDs;

__PACKAGE__->install_properties({
    columns => [ 'id', 'recipe_id', 'name', 'quantity' ],
    datasource => 'ingredients',
    primary_key => [ 'recipe_id', 'id' ],
    driver      => Data::ObjectDriver::Driver::Cache::Memcached->new(
        cache => Cache::Memcached->new({
            servers => [ '192.168.100.2:11211' ],
            debug   => 1,
        }),
        fallback => Data::ObjectDriver::Driver::DBI->new(
            dsn      => 'dbi:mysql:database=global',
            username => 'btrott',
            pk_generator => \&generate_pk,
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
