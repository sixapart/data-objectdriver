# $Id$

package Blog;
use strict;
use warnings;
use base 'Data::ObjectDriver::BaseObject';
use Data::ObjectDriver::Driver::DBI;
use DodTestUtil;

__PACKAGE__->install_properties({
    columns => ['id', 'parent_id', 'name'],
    datasource  => 'blog',
    primary_key => 'id',
    driver      => Data::ObjectDriver::Driver::DBI->new(dsn => DodTestUtil::dsn('global')),
});

1;
