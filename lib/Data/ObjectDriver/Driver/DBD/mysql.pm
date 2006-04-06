# $Id$

package Data::ObjectDriver::Driver::DBD::mysql;
use strict;
use warnings;

use base qw( Data::ObjectDriver::Driver::DBD );

use Carp qw( croak );

sub fetch_id { $_[3]->{mysql_insertid} || $_[3]->{insertid} }

1;
