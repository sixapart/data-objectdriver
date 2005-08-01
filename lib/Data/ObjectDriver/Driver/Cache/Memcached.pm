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
    my($class, $ids) = @_;
    return $driver->fallback->lookup_multi($class, $ids)
        if $driver->Disabled;

    my %id2key = map { $_ => $driver->cache_key($class, $_) } @$ids;
    my $got = $driver->cache->get_multi(values %id2key);

    ## If we got back all of the objects from the cache, return immediately.
    if (scalar keys %$got == @$ids) {
        return [ map $got->{ $id2key{$_} }, @$ids ];
    }

    ## Otherwise, look through the list of IDs to see what we're missing,
    ## and fall back to the backend to look up those objects.
    my @got;
    for my $id (@$ids) {
        if (my $obj = $got->{ $id2key{$id} }) {
            push @got, $obj;
        } else {
            my $obj = $driver->fallback->lookup($class, $id);
            if ($obj) {
                $driver->add_to_cache($driver->cache_key($class, $id),
                                      $obj->clone);
                push @got, $obj;
            }
        }
    }

    \@got;
}

1;
