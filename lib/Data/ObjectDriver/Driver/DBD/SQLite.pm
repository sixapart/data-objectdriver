# $Id

package Data::ObjectDriver::Driver::DBD::SQLite;
use strict;
use base qw( Data::ObjectDriver::Driver::DBD );

sub fetch_id { $_[2]->func('last_insert_rowid') }

1;
