# $Id$

use strict;

package My::BaseObject;
use base qw/Data::ObjectDriver::BaseObject/;

sub column_names {
    my $this = shift;
    my $cols = $this->SUPER::column_names(@_);
    push @$cols, 'rating';
    $cols;
}

package Wine;
use base qw( My::BaseObject );

use Data::ObjectDriver::Driver::DBI;

__PACKAGE__->install_properties({
    columns => [ 'id', 'cluster_id', 'name' ], # rating is defined on the fly in My::BaseObject 
    datasource => 'wines',
    primary_key => 'id',
    driver => Data::ObjectDriver::Driver::DBI->new(
        dsn      => 'dbi:mysql:database=yk-test-global',
        username => 'root',
    ),
});

sub insert {
    my $obj = shift;
    ## Choose a cluster for this recipe. This isn't a very solid way of
    ## doing this, but it works for testing.
    $obj->cluster_id(int(rand 2) + 1);
    $obj->SUPER::insert(@_);
}
#
1;