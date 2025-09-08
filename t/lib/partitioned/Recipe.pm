# $Id$

package Recipe;
use strict;
use warnings;
use base qw( Data::ObjectDriver::BaseObject );
use DodTestUtil;

use Data::ObjectDriver::Driver::DBI;

__PACKAGE__->install_properties({
    columns => [ 'recipe_id', 'partition_id', 'title' ],
    datasource => 'recipes',
    primary_key => 'recipe_id',
    driver => Data::ObjectDriver::Driver::DBI->new(
        dsn      => DodTestUtil::dsn('global'),
        reuse_dbh => 1,
    ),
});

my %drivers;
__PACKAGE__->has_partitions(
    number => 2,
    get_driver => sub {
        my $cluster = shift;
        my $driver = $drivers{$cluster} ||= 
            Data::ObjectDriver::Driver::DBI->new(
                dsn => DodTestUtil::dsn('cluster' . $cluster),
                reuse_dbh => 1,
                @_,
            );
        return $driver;
    },
);

1;
