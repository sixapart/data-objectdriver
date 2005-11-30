# $Id$

package Data::ObjectDriver::BaseObject;
use strict;
use Carp ();

use Class::Trigger qw( pre_save post_load pre_search );

=pod

=over 4

=item * serves as a base class for all object classes

=item * proxies retrieve/save/etc methods to the driver

=back

=cut

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

sub column {
    my $obj = shift;
    my $col = shift or return;
    $obj->{column_values}->{$col} = shift if @_;
    $obj->{column_values}->{$col};
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
        # xxx this *should* be croak, but some app still uses inexistent columns
        Carp::carp("Cannot find column '$col' for class '" . ref($obj) . "'");
        return;
    }
    *$AUTOLOAD = sub {
        shift()->column($col, @_);
    };
    goto &$AUTOLOAD;
}

1;
