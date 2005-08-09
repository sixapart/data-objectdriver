# $Id$

package Data::ObjectDriver::Driver::BaseCache;
use strict;
use base qw( Data::ObjectDriver Class::Accessor::Fast
             Class::Data::Inheritable );

use Carp ();

__PACKAGE__->mk_accessors(qw( cache fallback ));
__PACKAGE__->mk_classdata(qw( Disabled ));

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
    return $driver->fallback->lookup($class, $id)
        if $driver->Disabled;
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
    my($class, $ids) = @_;
    return $driver->fallback->lookup_multi($class, @$ids)
        if $driver->Disabled;
    ## Use driver->lookup to look up each object in the cache, and fallback
    ## to the backend driver if object isn't found in the cache.
    my @got;
    for my $id (@$ids) {
        push @got, $driver->lookup($class, $id);
    }
    \@got;
}

sub search {
    my $driver = shift;
    return $driver->fallback->search(@_)
        if $driver->Disabled;
    my($class, $terms, $args) = @_;

    ## Tell the fallback driver to fetch only the primary columns,
    ## then run the search using the fallback.
    my $pk = $class->properties->{primary_key};
    my $old = $args->{fetchonly};
    $args->{fetchonly} = ref $pk eq 'ARRAY' ? $pk : [ $pk ];
    my $iter = $driver->fallback->search($class, $terms, $args);

    ## Create a new iterator that knows how to get an object from
    ## the backend, then look it up using this driver--that means
    ## that we'll pull it from the cache if it's already there.
    my $iter2 = sub {
        my $obj = $iter->() or return;
        return $driver->lookup($class, $obj->primary_key);
    };

    ## Now emulate the standard search behavior of returning an
    ## iterator in scalar context, and the full list in list context.
    if (wantarray) {
        my @objs;
        while (my $obj = $iter2->()) {
            push @objs, $obj;
        }
        return @objs;
    } else {
        return $iter2;
    }
}

sub update {
    my $driver = shift;
    my($obj) = @_;
    return $driver->fallback->update($obj)
        if $driver->Disabled;
    my $key = $driver->cache_key(ref($obj), $obj->primary_key);
    $driver->update_cache($key, $obj->clone);
    $driver->fallback->update($obj);
}

sub remove {
    my $driver = shift;
    my($obj) = @_;
    return $driver->fallback->remove($obj)
        if $driver->Disabled;
    $driver->remove_from_cache($driver->cache_key(ref($obj), $obj->primary_key));
    $driver->fallback->remove($obj);
}

sub cache_key {
    my $driver = shift;
    my($class, $id) = @_;
    join ':', $class, ref($id) eq 'ARRAY' ? @$id : $id;
}

sub DESTROY { }

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
