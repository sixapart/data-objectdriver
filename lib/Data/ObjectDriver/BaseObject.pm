# $Id$

package Data::ObjectDriver::BaseObject;
use strict;
use Carp ();

use Class::Trigger qw( pre_save post_save post_load pre_search
                       pre_insert post_insert pre_update post_update
                       pre_remove post_remove );

sub install_properties {
    my $class = shift;
    no strict 'refs';
    my($props) = @_;
    *{"${class}::__properties"} = sub { $props };
    $props;
}

sub properties {
    my $this = shift;
    my $class = ref($this) || $this;
    $class->__properties;
}

sub driver {
    my $class = shift;
    $class->properties->{driver} ||= $class->properties->{get_driver}->();
}

sub get_driver {
    my $class = shift;
    $class->properties->{get_driver} = shift if @_;
}

sub new { bless {}, shift }

sub primary_key_tuple {
    my $obj = shift;
    my $pk = $obj->properties->{primary_key};
    $pk = [ $pk ] unless ref($pk) eq 'ARRAY';
    $pk;
}

sub primary_key {
    my $obj = shift;
    my $pk = $obj->primary_key_tuple;
    my @val = map $obj->$_(), @$pk;
    @val == 1 ? $val[0] : \@val;
}

sub has_primary_key {
    my $obj = shift;
    my $val = $obj->primary_key;
    $val = [ $val ] unless ref($val) eq 'ARRAY';
    for my $v (@$val) {
        return 0 unless defined $v;
    }
    1;
}

sub datasource { $_[0]->properties->{datasource} }

sub columns_of_type {
    my $obj = shift;
    my($type) = @_;
    my $props = $obj->properties;
    my $cols = $props->{columns};
    my $col_defs = $props->{column_defs};
    my @cols;
    for my $col (@$cols) {
        push @cols, $col if $col_defs->{$col} && $col_defs->{$col} eq $type;
    }
    \@cols;
}

sub set_values {
    my $obj = shift;
    my($values) = @_;
    my @cols = @{ $obj->column_names };
    for my $col (@cols) {
        next unless exists $values->{$col};
        $obj->column($col, $values->{$col});
    }
}

sub clone {
    my $obj = shift;
    my $clone = $obj->clone_all;
    for my $pk ($obj->primary_key_tuple) {
        $clone->$pk(undef);
    }
    $clone;
}

sub clone_all {
    my $obj = shift;
    my $clone = ref($obj)->new();
    $clone->set_values($obj->column_values);
    $clone;
}

sub has_column {
    my $obj = shift;
    my($col) = @_;
    $obj->{__col_names} ||= { map { $_ => 1 } @{ $obj->column_names } };
    exists $obj->{__col_names}->{$col};
}

sub column_names {
    ## Reference to a copy.
    [ @{ shift->properties->{columns} } ]
}

sub column_values { $_[0]->{'column_values'} }

## In 0.1 version we didn't die on inexistent column
## which might lead to silent bugs
## You should override column if you want to find the old 
## behaviour
sub column {
    my $obj = shift;
    my $col = shift or return;
    unless ($obj->has_column($col)) {
        Carp::croak("Cannot find column '$col' for class '" . ref($obj) . "'");
    }

    if (@_) {
         $obj->{column_values}->{$col} = shift;
        $obj->{changed_cols}->{$col}++;
    }
        
    $obj->{column_values}->{$col};
}

sub reset_changed_cols {
    my $obj = shift;
    $obj->{changed_cols} = {};
    1;
}

sub changed_cols {
    my $obj = shift;
    keys %{$obj->{changed_cols}};
}

sub exists {
    my $obj = shift;
    return 0 unless $obj->has_primary_key;
    $obj->_proxy('exists', @_);
}

sub save {
    my $obj = shift;
    if ($obj->exists) {
        return $obj->update;
    } else {
        return $obj->insert;
    }
}

sub lookup          { shift->_proxy('lookup',       @_) }
sub lookup_multi    { shift->_proxy('lookup_multi', @_) }
sub search          { shift->_proxy('search',       @_) }
sub remove          { shift->_proxy('remove',       @_) }
sub update          { shift->_proxy('update',       @_) }
sub insert          { shift->_proxy('insert',       @_) }
sub fetch_data      { shift->_proxy('fetch_data',   @_) }

sub refresh {
    my $obj = shift; 
    return unless $obj->has_primary_key;
    my $fields = $obj->fetch_data;
    $obj->set_values($fields);
    # XXX not sure this is the right place
    $obj->call_trigger('post_load');
    return 1;
}

sub _proxy {
    my $obj = shift;
    my($meth, @args) = @_;
    $obj->driver->$meth($obj, @args);
}

sub DESTROY { }

our $AUTOLOAD;
sub AUTOLOAD {
    my $obj = $_[0];
    (my $col = $AUTOLOAD) =~ s!.+::!!;
    no strict 'refs';
    Carp::croak("Cannot find method '$col' for class '$obj'") unless ref $obj;
    unless ($obj->has_column($col)) {
        Carp::croak("Cannot find column '$col' for class '" . ref($obj) . "'");
    }
    *$AUTOLOAD = sub {
        shift()->column($col, @_);
    };
    goto &$AUTOLOAD;
}

1;
__END__

=head1 NAME

Data::ObjectDriver::BaseObject - base class for modeled objects

=head1 SYNOPSIS

See synopsis in I<Data::ObjectDriver>.

=head1 DESCRIPTION

I<Data::ObjectDriver::BaseObject> provides services to data objects modeled
with the I<Data::ObjectDriver> object relational mapper.

=head1 USAGE

=head2 Class->install_properties({ ... })

=head2 Class->properties

=head2 Class->driver

Returns the database driver for this class, invoking the class's I<get_driver>
function if necessary.

=head2 Class->get_driver($driver)

Sets the function used to find the object driver for I<Class> objects.

=head2 $obj->primary_key

Returns the B<values> of the primary key fields of I<$obj>.

=head2 Class->primary_key_tuple

Returns the B<names> of the primary key fields for objects of class I<Class>.

=head2 $obj->has_primary_key

=head2 $obj->clone

Returns a new object of the same class as I<$obj> containing the same data,
except for primary keys, which are set to C<undef>.

=head2 $obj->clone_all

Returns a new object of the same class as I<$obj> containing the same data,
including all key fields.

=head2 $obj->...

=cut

