# $Id$

package Data::ObjectDriver::Driver::BaseCache;
use strict;
use base qw( Data::ObjectDriver Class::Accessor::Fast );

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
    my $key = $driver->cache_key($class, $id);
    my $obj = $driver->get_from_cache($key);
    unless ($obj) {
        $obj = $driver->fallback->lookup($class, $id);
        $driver->add_to_cache($key, $obj->clone) if $obj;
    }
    $obj;
}

sub lookup_multi {
    my $driver = shift;
    my($class, @ids) = @_;
    my %got;
    for my $id (@ids) {
        my $obj = $driver->get_from_cache($driver->cache_key($class, $id));
        $got{$id} = $obj if $obj;
    }
    \%got;
}

sub update {
    my $driver = shift;
    my($obj) = @_;
    my $key = $driver->cache_key(ref($obj), $obj->primary_key);
    $driver->update_cache($key, $obj->clone);
    $driver->fallback->update($obj);
}

sub remove {
    my $driver = shift;
    my($obj) = @_;
    $driver->remove_from_cache($driver->cache_key(ref($obj), $obj->primary_key));
    $driver->fallback->remove($obj);
}

sub cache_key {
    my $driver = shift;
    my($class, $id) = @_;
    join ':', $class, ref($id) eq 'ARRAY' ? @$id : $id;
}

our $AUTOLOAD;
sub AUTOLOAD {
    my $driver = $_[0];
    (my $meth = $AUTOLOAD) =~ s/.+:://;
    no strict 'refs';
    Carp::croak("Cannot call method '$meth' on object '$driver'")
        unless $driver->fallback->can($meth);
    *$AUTOLOAD = sub {
        shift->fallback->$meth(@_);
    };
    goto &$AUTOLOAD;
}

1;
