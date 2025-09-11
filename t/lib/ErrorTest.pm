# $Id$

package ErrorTest;
use strict;
use warnings;
use base qw( Data::ObjectDriver::BaseObject );
use DodTestUtil;

use Data::ObjectDriver::Driver::DBI;

__PACKAGE__->install_properties({
    columns => [ 'foo' ],
    datasource => 'error_test',
    primary_key =>  [ ],
    driver => Data::ObjectDriver::Driver::DBI->new(
        dsn      => DodTestUtil::dsn('global'),
    ),
});
