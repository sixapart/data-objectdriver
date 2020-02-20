# $Id$

package Ingredient;
use strict;
use base qw( Data::ObjectDriver::BaseObject );
use DodTestUtil;

use Data::ObjectDriver::Driver::DBI;

our $ID = 0;

__PACKAGE__->install_properties({
    columns => [ 'id', 'name', 'quantity' ],
    datasource => 'ingredients',
    primary_key => 'id',
    driver      => Data::ObjectDriver::Driver::DBI->new(
            dsn      => DodTestUtil::dsn('global'),
            pk_generator => \&generate_pk,
    ),
});

sub generate_pk {
    my($obj) = @_;
    $obj->id(++$ID);
    1;
}

1;
