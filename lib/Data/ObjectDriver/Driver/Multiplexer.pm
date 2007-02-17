# $Id$

package Data::ObjectDriver::Driver::Multiplexer;
use strict;
use warnings;

use Storable();

use base qw( Data::ObjectDriver Class::Accessor::Fast );

__PACKAGE__->mk_accessors(qw( on_search on_lookup drivers ));

use Carp qw( croak );

sub init {
    my $driver = shift;
    $driver->SUPER::init(@_);
    my %param = @_;
    for my $key (qw( on_search on_lookup drivers )) {
        $driver->$key( $param{$key} );
    }
    return $driver;
}

sub lookup {
    my $driver = shift;
    my $subdriver = $driver->on_lookup;
    croak "on_lookup is not defined in $driver"
        unless $subdriver;
    return $subdriver->lookup(@_);
}

sub lookup_multi {
    my $driver = shift;
    my $subdriver = $driver->on_lookup;
    croak "on_lookup is not defined in $driver"
        unless $subdriver;
    return $subdriver->lookup_multi(@_);
}

sub exists {
    my $driver = shift;
    my($class, $terms, $args) = @_;
    ## just assume that the first driver declared is the more efficient one
    my $sub_driver = $driver->drivers->[0];
    return $sub_driver->exists(@_);
}

sub search {
    my $driver = shift;
    my($class, $terms, $args) = @_;
    my $sub_driver = $driver->_find_sub_driver($terms)
        or croak "No matching sub-driver found";
    return $sub_driver->search(@_);
}

sub replace { shift->_exec_multiplexed('replace', @_) }
sub insert  { shift->_exec_multiplexed('insert',  @_) }

sub update {
    croak "update is not implemented in ", __PACKAGE__;
}

sub remove {
    my $driver = shift;
    my(@stuff) = @_;
    my $stuff = $stuff[0];
    my $terms = $stuff[1];
    if (ref $stuff) {
        ## hackish... use on_search as a to_hash() method 
        $terms = { map { $_ => $stuff->$_() } keys %{ $driver->on_search } };
    }
    my $removed = 0;
    for my $key (keys %{ $terms }) {
        my $sub_driver = $driver->on_search->{$key} or next;
        $removed += $sub_driver->remove(@stuff);
    }
    return $removed;
}

sub _find_sub_driver {
    my $driver = shift;
    my($terms) = @_;
    for my $key (keys %$terms) {
        if (my $sub_driver = $driver->on_search->{$key}) {
            return $sub_driver;
        }
    }
}

sub _exec_multiplexed {
    my $driver = shift;
    my($meth, $obj, @args) = @_;
    my $orig_obj = Storable::dclone($obj);
    my $ret;
    ## We want to be sure to have the initial and final state of the object
    ## strictly identical as if we made only one call on $obj
    ## (Perhaps it's a bit overkill ? playing with 'changed_cols' may suffice)
    for my $sub_driver (@{ $driver->drivers }) {
        $obj = Storable::dclone($orig_obj);
        $ret = $sub_driver->$meth($obj, @args);
    }
    return $ret;
}

## Nobody should ask a dbh for us directly, if someone does, this
## is probably to change handler properties (transaction). So 
## we assume that only the on_lookup is important (I said it was experimental..)
sub get_dbh {
    my $driver = shift;
    my $subdriver = $driver->on_lookup;
    return $subdriver->get_dbh(@_);
}

1;
__END__

=head1 NAME

Data::ObjectDriver::Driver::Multiplexer - Multiplex multiple partitioned drivers

=head1 SYNOPSIS

    package MappingTable;

    use Foo;
    use Bar;

    my $foo_driver = Foo->driver;
    my $bar_driver = Bar->driver;

    __PACKAGE__->install_properties({
        columns => [ qw( foo_id bar_id value ) ],
        primary_key => 'foo_id',
        driver => Data::ObjectDriver::Driver::Multiplexer->new(
            on_search => {
                foo_id => $foo_driver,
                bar_id => $bar_driver,
            },
            on_lookup => $foo_driver,
            drivers => [ $foo_driver, $bar_driver ],
        ),
    });

=head1 DESCRIPTION

I<Data::ObjectDriver::Driver::Multiplexer> associates a set of drivers to
a particular class. In practice, this means that all INSERTs and DELETEs
are propagated to all associated drivers (for example, all associated
databases or tables in a database), and that SELECTs are sent to the
appropriate multiplexed driver, based on partitioning criteria.

Note that this driver has the following limitations currently:

=over 4

=item 1. It's very experimental.

=item 2. It's very experimental.

=item 3. IT'S VERY EXPERIMENTAL.

=item 4. This documentation you're reading is incomplete. the api is likely
to evolve  

=back

=cut
