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
    # rating is defined on the fly in My::BaseObject 
    columns => [ 'id', 'cluster_id', 'name', 'content', 'binchar'],
    datasource => 'wines',
    primary_key => 'id',
    column_defs => { content => 'blob', binchar => 'binchar' },
    driver => Data::ObjectDriver::Driver::DBI->new(
        dsn      => 'dbi:SQLite:dbname=global.db',
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
