# $Id$

package Data::ObjectDriver::Driver::Cache::RAM;
use strict;
use base qw( Data::ObjectDriver::Driver::BaseCache );

our %Cache;

sub init {
    my $driver = shift;
    my %param  = @_;
    $param{cache} ||= 1; # hack
    $driver->SUPER::init(%param);
}

sub get_from_cache    { $Cache{$_[1]}         }
sub add_to_cache      { $Cache{$_[1]} = $_[2] }
sub update_cache      { $Cache{$_[1]} = $_[2] }
sub remove_from_cache { delete $Cache{$_[1]}  }

1;
