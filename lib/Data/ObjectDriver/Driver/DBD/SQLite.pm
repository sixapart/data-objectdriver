# $Id

package Data::ObjectDriver::Driver::DBD::SQLite;
use strict;
use base qw( Data::ObjectDriver::Driver::DBD );

sub fetch_id { $_[2]->func('last_insert_rowid') }

sub bind_param_attributes {
    my ($dbd, $data_type) = @_;
    if ($data_type) { 
        if ($data_type eq 'blob') {
            return DBI::SQL_BLOB;
        } elsif ($data_type eq 'binchar') {
            return DBI::SQL_BINARY;
        }
    }
    return undef;
}

1;

=pod

=head1 NAME

Data::ObjectDriver SQLite driver

=head2 DESCRIPTION

This class provides an interface to the SQLite (L<http://sqlite.org>)
database through DBI.

=head2 NOTES & BUGS

This is experimental.

With the 1.11 version of L<DBD::SQLite> Blobs are handled transparently,
so C<bind_param_attributes> is optionnal.
With previous version of L<DBD::SQLite> users have experimented issues
with binary data in CHAR (partially solved by the DBI::SQL_BINARY binding). 

=cut
