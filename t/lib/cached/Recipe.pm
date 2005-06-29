# $Id$

package Recipe;
use strict;
use base qw( Data::ObjectDriver::BaseObject );

use Data::ObjectDriver::Driver::DBI;

__PACKAGE__->install_properties({
    columns => [ 'id', 'title' ],
    datasource => 'recipes',
    primary_key => 'id',
    driver => Data::ObjectDriver::Driver::DBI->new(
        dsn      => 'dbi:mysql:database=global',
        username => 'btrott',
    ),
});

1;
