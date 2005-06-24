# $Id$

package Data::ObjectDriver::Driver::Cache::Memcached;
use strict;
use base qw( Data::ObjectDriver::Driver::BaseCache );

use Cache::Memcached;
use Carp ();

sub add_to_cache      { shift->cache->add(@_)    }
sub update_cache      { shift->cache->set(@_)    }
sub remove_from_cache { shift->cache->delete(@_) }
sub get_from_cache    { shift->cache->get(@_)    }

sub lookup_multi {
    my $driver = shift;
    my($class, @ids) = @_;
    my @keys = map $driver->_cache_key($class, $_), @ids;
    $driver->cache->get_multi(@ids);
}

1;
