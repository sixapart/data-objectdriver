# $Id: Wine.pm 1050 2005-12-08 13:46:22Z ykerherve $

use strict;

package PkLess;
use base qw/Data::ObjectDriver::BaseObject/;

use Data::ObjectDriver::Driver::DBI;

__PACKAGE__->install_properties({
    columns => [ 'anything' ],
    datasource => 'pkless',
    primary_key =>  [ ], # proper way to skip pk (for now XXX)
    driver => Data::ObjectDriver::Driver::DBI->new(
        dsn      => 'dbi:SQLite:dbname=global.db',
    ),
});
