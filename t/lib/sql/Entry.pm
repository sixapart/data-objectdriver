# $Id$

package Entry;
use strict;
use warnings;
use base 'Data::ObjectDriver::BaseObject';
use Data::ObjectDriver::Driver::DBI;
use DodTestUtil;

__PACKAGE__->install_properties({
    columns => ['id', 'blog_id', 'title', 'text'],
    datasource  => 'entry',
    primary_key => 'id',
    driver      => Data::ObjectDriver::Driver::DBI->new(dsn => DodTestUtil::dsn('global')),
});

1;
