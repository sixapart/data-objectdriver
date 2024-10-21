# $Id$

package Foo;
use strict;
use warnings;
use Data::ObjectDriver::Driver::DBI;
use DodTestUtil;
use base qw( Data::ObjectDriver::BaseObject );

__PACKAGE__->install_properties({
    columns     => ['id', 'name', 'text'],
    column_defs => {
        'id'   => 'integer not null auto_increment',
        'name' => 'string(25)',
        'text' => 'text',
    },
    datasource  => 'foo',
    primary_key => 'id',
    driver      => Data::ObjectDriver::Driver::DBI->new(dsn => DodTestUtil::dsn('global')),
});

1;
