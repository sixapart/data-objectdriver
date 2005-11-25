# $Id

package Data::ObjectDriver::Driver::DBD::SQLite;
use strict;
use base qw( Data::ObjectDriver::Driver::DBD );

sub fetch_id { $_[2]->func('last_insert_rowid') }

sub bind_param_attributes {
    my ($dbd, $data_type) = @_;
    if ($data_type && $data_type eq 'blob') {
        return DBI::SQL_BLOB;
    }
    return undef;
}

1;
