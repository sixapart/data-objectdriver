# $Id$

package Data::ObjectDriver::Driver::Memcached;
use strict;
use base qw( Data::ObjectDriver Class::Accessor::Fast );

use Cache::Memcached;
use Carp ();

__PACKAGE__->mk_accessors(qw( cache fallback ));

sub init {
    my $driver = shift;
    $driver->SUPER::init(@_);
    my %param = @_;
    $driver->cache($param{cache})
        or Carp::croak("cache is required");
    $driver->fallback($param{fallback})
        or Carp::croak("fallback is required");
    $driver;
}

sub lookup {
    my $driver = shift;
    my($class, $id) = @_;
    my $key = $driver->_cache_key($class, $id);
    my $cache = $driver->cache;
    my $obj = $cache->get($key);
    unless ($obj) {
        $obj = $driver->fallback->lookup($class, $id);
        $driver->cache->add($key, $obj->clone) if $obj;
    }
    $obj;
}

sub lookup_multi {
    my $driver = shift;
    my($class, @ids) = @_;
    my @keys = map $driver->_cache_key($class, $_), @ids;
    $driver->cache->get_multi(@ids);
}

sub update {
    my $driver = shift;
    my($obj) = @_;
    my $clone = $obj->clone;
    my $cache = $driver->cache;
    my $key = $driver->_cache_key(ref($obj), $obj->primary_key);
    if ($cache->get($key)) {
        $cache->replace($key, $clone);
    } else {
        $cache->set($key, $clone);
    }
    $driver->fallback->update($obj);
}

sub remove {
    my $driver = shift;
    my($obj) = @_;
    $driver->cache->delete($driver->_cache_key(ref($obj), $obj->primary_key));
    $driver->fallback->remove($obj);
}

sub search       { shift->_call_fallback('search',      @_) }
sub insert       { shift->_call_fallback('insert',      @_) }
sub exists       { shift->_call_fallback('exists',      @_) }

sub _call_fallback {
    my $driver = shift;
    my($meth, @args) = @_;
    $driver->fallback->$meth(@args);
}

sub _cache_key {
    my $driver = shift;
    my($class, $id) = @_;
    join ':', $class, ref($id) eq 'ARRAY' ? @$id : $id;
}

1;
