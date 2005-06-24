# $Id$

package Data::ObjectDriver::Driver::DBI::Pg;
use strict;
use base qw( Data::ObjectDriver::Driver::DBI );

sub init_db {
    my $driver = shift;
    my $dbh = $driver->SUPER::init_db(@_);
    $dbh->do("set timezone to 'UTC'");
    $dbh;
}

sub bind_param_attributes {
    my ($driver, $data_type) = @_;
    if ($data_type && $data_type eq 'blob') {
        return { pg_type => DBD::Pg::PG_BYTEA() };
    }
    return undef;
}

sub sequence_name {
    my $driver = shift;
    my($class) = @_;
    return join '_', $class->datasource, 'seq';
}

sub fetch_id {
    my $driver = shift;
    my($class, $dbh, $sth) = @_;
    $dbh->last_insert_id(undef, undef, undef, undef,
        { sequence => $driver->sequence_name($class) });
}

1;
