# $Id$

package Recipe;
use strict;
use base qw( Data::ObjectDriver::BaseObject );
use DodTestUtil;

use Data::ObjectDriver::Driver::DBI;
use Data::ObjectDriver::Driver::Cache::RAM;

__PACKAGE__->install_properties({
    columns => [ 'recipe_id', 'title' ],
    datasource => 'recipes',
    primary_key => 'recipe_id',
    driver      => Data::ObjectDriver::Driver::Cache::RAM->new(
        fallback => Data::ObjectDriver::Driver::DBI->new(
            dsn      => DodTestUtil::dsn('global'),
            reuse_dbh => 1,
        ),
    ),
});

1;
