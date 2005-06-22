# $Id$

package Data::ObjectDriver::Driver::Partition;
use strict;
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
    $driver->get_driver->(@ids)->lookup_multi($class, @ids);
}

sub exists { shift->_exec_partitioned('exists', @_) }
sub insert { shift->_exec_partitioned('insert', @_) }
sub update { shift->_exec_partitioned('update', @_) }
sub remove { shift->_exec_partitioned('remove', @_) }

sub search {
    my $driver = shift;
    my($class, $terms, $args) = @_;
    $driver->get_driver->($terms)->search($class, $terms, $args);
}

sub _exec_partitioned {
    my $driver = shift;
    my($meth, $obj) = @_;
    $driver->get_driver->($obj->primary_key)->$meth($obj);
}

1;
