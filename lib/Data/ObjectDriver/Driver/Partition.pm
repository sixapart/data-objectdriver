# $Id$

package Data::ObjectDriver::Driver::Partition;
use strict;
use warnings;

use base qw( Data::ObjectDriver Class::Accessor::Fast );

__PACKAGE__->mk_accessors(qw( get_driver ));

sub init {
    my $driver = shift;
    $driver->SUPER::init(@_);
    my %param = @_;
    $driver->get_driver($param{get_driver});
    $driver;
}

sub lookup {
    my $driver = shift;
    my($class, $id) = @_;
    $driver->get_driver->($id)->lookup($class, $id);
}

sub lookup_multi {
    my $driver = shift;
    my($class, @ids) = @_;
    $driver->get_driver->($ids[0])->lookup_multi($class, @ids);
}

sub exists     { shift->_exec_partitioned('exists',     @_) }
sub insert     { shift->_exec_partitioned('insert',     @_) }
sub update     { shift->_exec_partitioned('update',     @_) }
sub remove     { shift->_exec_partitioned('remove',     @_) }
sub fetch_data { shift->_exec_partitioned('fetch_data', @_) }

sub search {
    my $driver = shift;
    my($class, $terms, $args) = @_;
    $driver->get_driver->($terms, $args)->search($class, $terms, $args);
}

sub _exec_partitioned {
    my $driver = shift;
    my($meth, $obj, @rest) = @_;
    ## If called as a class method, pass in the stuff in @rest.
    my $d;
    if (ref($obj)) {
        my $arg = $obj->is_pkless ? $obj->column_values : $obj->primary_key;
        $d = $driver->get_driver->($arg);
    } else {
        $d = $driver->get_driver->(@rest);
    }
    $d->$meth($obj, @rest);
}

1;
