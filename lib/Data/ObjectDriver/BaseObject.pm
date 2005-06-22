# $Id$

package Data::ObjectDriver::BaseObject;
use strict;

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

sub new { bless {}, shift }

sub primary_key {
    my $obj = shift;
    my $pk = $obj->properties->{primary_key};
    $pk = [ $pk ] unless ref($pk) eq 'ARRAY';
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

sub column_names {
    my $obj = shift;
    my $props = $obj->properties;
    my @cols = @{ $props->{columns} };
    push @cols, qw( created_on modified_on )
        if $props->{audit};
    \@cols;
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

sub _proxy {
    my $obj = shift;
    my($meth, @args) = @_;
    $obj->properties->{driver}->$meth($obj, @args);
}

our $AUTOLOAD;
sub AUTOLOAD {
    my $obj = $_[0];
    (my $col = $AUTOLOAD) =~ s!.+::!!;
    no strict 'refs';
    die "Cannot find method '$col' for class '$obj'" unless ref $obj;
    *$AUTOLOAD = sub {
        shift()->column($col, @_);
    };
    goto &$AUTOLOAD;
}

1;
