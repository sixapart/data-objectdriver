# $Id$

package Data::ObjectDriver::Driver::BaseCache;
use strict;
use warnings;

use base qw( Data::ObjectDriver Class::Accessor::Fast
             Class::Data::Inheritable );

use Carp ();

__PACKAGE__->mk_accessors(qw( cache fallback ));
__PACKAGE__->mk_classdata(qw( Disabled ));

sub deflate { $_[1] }
sub inflate { $_[2] }

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

sub cache_object {
    my $driver = shift;
    my($obj) = @_;
    ## If it's already cached in this layer, assume it's already cached in
    ## all layers below this, as well.
    unless (exists $obj->{__cached} && $obj->{__cached}{ref $driver}) {
        $driver->add_to_cache(
                $driver->cache_key(ref($obj), $obj->primary_key),
                $driver->deflate($obj)
            );
        $driver->fallback->cache_object($obj);
    }
}

sub lookup {
    my $driver = shift;
    my($class, $id) = @_;
    return $driver->fallback->lookup($class, $id)
        if $driver->Disabled;
    my $key = $driver->cache_key($class, $id);
    my $obj = $driver->get_from_cache($key);
    if ($obj) {
        $obj = $driver->inflate($class, $obj);
        $obj->{__cached}{ref $driver} = 1;
    } else {
        $obj = $driver->fallback->lookup($class, $id);
    }
    $obj;
}

sub get_multi_from_cache {
    my $driver = shift;
    my(@keys) = @_;
    ## Use driver->get_from_cache to look up each object in the cache.
    ## We don't fall back here, because we only want to find items that
    ## are already cached.
    my %got;
    for my $key (@keys) {
        my $obj = $driver->get_from_cache($key) or next;
        $got{$key} = $obj;
    }
    \%got;
}

sub lookup_multi {
    my $driver = shift;
    my($class, $ids) = @_;
    return $driver->fallback->lookup_multi($class, $ids)
        if $driver->Disabled;

    my %id2key = map { $_ => $driver->cache_key($class, $_) } @$ids;
    my $got = $driver->get_multi_from_cache(values %id2key);

    ## If we got back all of the objects from the cache, return immediately.
    if (scalar keys %$got == @$ids) {
        my @objs;
        for my $id (@$ids) {
            my $obj = $driver->inflate($class, $got->{ $id2key{$id} });
            $obj->{__cached}{ref $driver} = 1;
            push @objs, $obj;
        }
        return \@objs;
    }

    ## Otherwise, look through the list of IDs to see what we're missing,
    ## and fall back to the backend to look up those objects.
    my($i, @got, @need, %need2got) = (0);
    for my $id (@$ids) {
        if (my $obj = $got->{ $id2key{$id} }) {
            $obj = $driver->inflate($class, $obj);
            $obj->{__cached}{ref $driver} = 1;
            push @got, $obj;
        } else {
            push @got, undef;
            push @need, $id;
            $need2got{$#need} = $i;
        }
        $i++;
    }

    if (@need) {
        my $more = $driver->fallback->lookup_multi($class, \@need);
        $i = 0;
        for my $obj (@$more) {
            $got[ $need2got{$i++} ] = $obj;
        }
    }

    \@got;
}

## We fallback by default
sub fetch_data { 
    my $driver = shift;
    my ($obj) = @_;
    return $driver->fallback->fetch_data($obj);
}

sub search {
    my $driver = shift;
    return $driver->fallback->search(@_)
        if $driver->Disabled;
    my($class, $terms, $args) = @_;

    ## If the caller has asked only for certain columns, assume that
    ## he knows what he's doing, and fall back to the backend.
    return $driver->fallback->search(@_)
        if $args->{fetchonly};

    ## Tell the fallback driver to fetch only the primary columns,
    ## then run the search using the fallback.
    local $args->{fetchonly} = $class->primary_key_tuple; 
    ## Disable triggers for this load. We don't want the post_load trigger
    ## being called twice.
    $args->{no_triggers} = 1;
    my @objs = $driver->fallback->search($class, $terms, $args);

    ## Load all of the objects using a lookup_multi, which is fast from
    ## cache.
    my $objs = $driver->lookup_multi($class, [ map { $_->primary_key } @objs ]);

    $driver->list_or_iterator($objs);
}

sub update {
    my $driver = shift;
    my($obj) = @_;
    return $driver->fallback->update($obj)
        if $driver->Disabled;
    my $key = $driver->cache_key(ref($obj), $obj->primary_key);
    $driver->update_cache($key, $driver->deflate($obj));
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
    if ($class->can('cache_class')) {
        $class = $class->cache_class;
    }
    my $key = join ':', $class, ref($id) eq 'ARRAY' ? @$id : $id;
    if (my $v = $class->can('cache_version')) {
        $key .= ':' . $v->();
    }
    return $key;
}

sub DESTROY { }

sub AUTOLOAD {
    my $driver = $_[0];
    (my $meth = our $AUTOLOAD) =~ s/.+:://;
    no strict 'refs';
    my $fallback = $driver->fallback;
    ## Check for invalid methods, but make sure we still allow
    ## chaining 2 caching drivers together.
    Carp::croak("Cannot call method '$meth' on object '$driver'")
        unless $fallback->can($meth) ||
               UNIVERSAL::isa($fallback, __PACKAGE__);
    *$AUTOLOAD = sub {
        shift->fallback->$meth(@_);
    };
    goto &$AUTOLOAD;
}

1;
