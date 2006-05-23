# $Id$

package Data::ObjectDriver::Driver::DBD::mysql;
use strict;
use warnings;
use base qw( Data::ObjectDriver::Driver::DBD );

use Carp qw( croak );
use Data::ObjectDriver::Errors;

use constant ERROR_MAP => {
    1062 => Data::ObjectDriver::Errors->UNIQUE_CONSTRAINT,
};

sub fetch_id { $_[3]->{mysql_insertid} || $_[3]->{insertid} }

sub map_error_code {
    my $dbd = shift;
    my($code, $msg) = @_;
    return ERROR_MAP->{$code};
}

1;
