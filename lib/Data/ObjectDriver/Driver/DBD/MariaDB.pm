# $Id$

package Data::ObjectDriver::Driver::DBD::MariaDB;
use strict;
use warnings;
use base qw( Data::ObjectDriver::Driver::DBD::mysql );

sub fetch_id { $_[3]->{mariadb_insertid} || $_[3]->{insertid} }

sub bind_param_attributes {
    my ($dbd, $data_type) = @_;
    if ($data_type) {
        if ($data_type eq 'blob') {
            return DBI::SQL_BINARY;
        } elsif ($data_type eq 'binchar') {
            return DBI::SQL_BINARY;
        }
    }
    return;
}

1;
