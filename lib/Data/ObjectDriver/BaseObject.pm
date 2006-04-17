# $Id$

package Data::ObjectDriver::BaseObject;
use strict;
use warnings;

use Scalar::Util qw(weaken);
use Carp ();

use Class::Trigger qw( pre_save post_save post_load pre_search
                       pre_insert post_insert pre_update post_update
                       pre_remove post_remove );

sub install_properties {
    my $class = shift;
    no strict 'refs';
    my($props) = @_;
    *{"${class}::__properties"} = sub { $props };

    # predefine getter/setter methods here
    foreach my $col (@{ $props->{columns} }) {
        # Skip adding this method if the class overloads it.
        # this lets the SUPER::columnname magic do it's thing
        if (!defined (*{"${class}::$col"})) {
            *{"${class}::$col"} = sub {
                shift()->column($col, @_);
            };
        }
    }
    $props;
}

sub properties {
    my $this = shift;
    my $class = ref($this) || $this;
    $class->__properties;
}

# see docs below

sub has_a {
    my $class = shift;
    my %args = @_;

    my $props = $obj->properties;

    die "No properties defined for $class" unless ($props);

    # Iterate over each remote object
    foreach my $parentclass (keys %args) {
        my $config = $args{$parentclass};
        next unless $config;
 
        # Parameters
        my $column = $config->{column};
        my $method = $config->{method};
        my $cached = $config->{cached} || 0;
        my $parent_method = $config->{parent_method};

        # column is required
        if (!defined($column)) {
            die "Please specify a valid column for $parentclass" 
        }
        # TBD Is column a composite key?

        # create a method name based on the column
        if (! defined $method) {
            $method = $column;
            $method =~ s/_id$//;
            $method .= "_obj";
        }

        # die if we can't find a way to make a valid method
        # TBD check current list of columns to avoid clash
        if (! defined $method || ($method eq $column)) {
            die "Please define a valid method for $class->$column";
        }

        no strict 'refs';

        if ($cached) {
            # Store cached item inside this object's namespace
            my $cachekey = "__cache_$method";

            *{"${class}::$method"} = sub {
                my $obj = shift;
                unless (exists $obj->{$cachekey}) {
                    $obj->{$cachekey} = $parentclass->lookup($obj->column($column));
                    weaken $obj->{$cachekey};
                }
                return $obj->{$cachekey};
            };
        } else {
            *{"${class}::$method"} = sub {
                return $parentclass->lookup(shift()->column($column));
            };
        }

        # now add to the parent
        if (!defined $parent_method) {
            $parent_method = lc($class);
            $parent_method =~ s/^.*:://; 

            $parent_method .= '_objs';
        }
        *{"${parentclass}::$parent_method"} = sub {
            my $obj = shift;
            my $terms = shift;
            my $args = shift;
            # TBD - allow user defined extra terms here?...
            # TBD - use primary_key_to_terms
            return $class->search({$column => $obj->id}, $args);
        };
    } # end of loop over class names
    return;
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

sub is_pkless {
    my $obj = shift;
    my $prop_pk = $obj->properties->{primary_key};
    return 1 if ! $prop_pk;
    return 1 if ref $prop_pk eq 'ARRAY' && ! @$prop_pk;
}

sub primary_key_tuple {
    my $obj = shift;
    my $pk = $obj->properties->{primary_key};
    $pk = [ $pk ] unless ref($pk) eq 'ARRAY';
    $pk;
}

sub primary_key {
    my $obj = shift;
    my $pk = $obj->primary_key_tuple;
    my @val = map { $obj->$_() }  @$pk;
    @val == 1 ? $val[0] : \@val;
}

sub is_same_array {
    my($a1, $a2) = @_;
    return if ($#$a1 != $#$a2);
    for (my $i = 0; $i <= $#$a1; $i++) {
        return if $a1->[$i] ne $a2->[$i];
    }
    return 1;
}

sub primary_key_to_terms {
    my($obj, $id) = @_;
    my $pk = $obj->primary_key_tuple;
    if (! defined $id) { 
        $id = $obj->primary_key;
    } else {
        if (ref($id) eq 'HASH') {
            my @keys = sort keys %$id;
            unless (is_same_array(\@keys, [ sort @$pk ])) {
                Carp::croak("keys don't match with primary keys: @keys");
            }
            return $id;
        }
    }
    $id = [ $id ] unless ref($id) eq 'ARRAY';
    my $i = 0;
    my %terms;
    @terms{@$pk} = @$id;
    \%terms;
}

sub has_primary_key {
    my $obj = shift;
    return unless @{$obj->primary_key_tuple};
    my $val = $obj->primary_key;
    $val = [ $val ] unless ref($val) eq 'ARRAY';
    for my $v (@$val) {
        return unless defined $v;
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
    my $values = shift;
    for my $col (keys %$values) {
        unless ( $obj->has_column($col) ) {
            Carp::croak("You tried to set inexistent column $col to value $values->{$col} on " . ref($obj));
        }
        $obj->column($col => $values->{$col});
    }
}

sub set_values_internal {
    my $obj = shift;
    my $values = shift;
    for my $col (keys %$values) {
        unless ( $obj->has_column($col) ) {
            Carp::croak("You tried to set inexistent column $col to value $values->{$col} on " . ref($obj));
        }
        $obj->column($col => $values->{$col}, { no_changed_flag => 1 });
    }
}

sub clone {
    my $obj = shift;
    my $clone = $obj->clone_all;
    for my $pk (@{ $obj->primary_key_tuple }) {
        $clone->$pk(undef);
    }
    $clone;
}

sub clone_all {
    my $obj = shift;
    my $clone = ref($obj)->new();
    $clone->set_values_internal($obj->column_values);
    $clone->{changed_cols} = $obj->{changed_cols};
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
        unless ($_[0] && ref($_[0]) eq 'HASH' && $_[0]->{no_changed_flag}) {
            $obj->{changed_cols}->{$col}++;
        }
    }
        
    $obj->{column_values}->{$col};
}

sub changed_cols {
    my $obj = shift;
    keys %{$obj->{changed_cols}};
}

sub is_changed {
    my $obj = shift;
    if (@_) {
        return exists $obj->{changed_cols}->{$_[0]};
    } else {
        my $pk = $obj->primary_key_tuple;
        my %pk = map { $_ => 1 } @$pk;
        my @changed_cols = grep {!$pk{$_}}  $obj->changed_cols;
        return @changed_cols > 0;
    }
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

sub lookup {
    my $class = shift;
    my $driver = $class->driver;
    my $obj = $driver->lookup($class, @_) or return;
    $driver->cache_object($obj);
    $obj;
}

sub lookup_multi {
    my $class = shift;
    my $driver = $class->driver;
    my $objs = $driver->lookup_multi($class, @_) or return;
    for my $obj (@$objs) {
        $driver->cache_object($obj) if $obj;
    }
    $objs;
}

sub search {
    my $class = shift;
    my($terms, $args) = @_;
    my $driver = $class->driver;
    my @objs = $driver->search($class, $terms, $args);

    ## Don't attempt to cache objects where the caller specified fetchonly,
    ## because they won't be complete.
    ## Also skip this step if we don't get any objects back from the search
    if (!$args->{fetchonly} || !@objs) {
        for my $obj (@objs) {
            $driver->cache_object($obj) if $obj;
        }
    }
    $driver->list_or_iterator(\@objs);
}

sub remove          { shift->_proxy('remove',       @_) }
sub update          { shift->_proxy('update',       @_) }
sub insert          { shift->_proxy('insert',       @_) }
sub fetch_data      { shift->_proxy('fetch_data',   @_) }

sub refresh {
    my $obj = shift; 
    return unless $obj->has_primary_key;
    my $fields = $obj->fetch_data;
    $obj->set_values_internal($fields);
    # XXX not sure this is the right place
    $obj->call_trigger('post_load');
    return 1;
}

sub _proxy {
    my $obj = shift;
    my($meth, @args) = @_;
    $obj->driver->$meth($obj, @args);
}

sub deflate { { columns => shift->column_values } }

sub inflate {
    my $class = shift;
    my($deflated) = @_;
    my $obj = $class->new;
    $obj->set_values_internal($deflated->{columns});
    $obj->{changed_cols} = {};
    $obj;
}

sub DESTROY { }

sub AUTOLOAD {
    my $obj = $_[0];
    (my $col = our $AUTOLOAD) =~ s!.+::!!;
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

Sets up columns, indexes, primary keys, etc.

=head2 Class->properties

Returns the list of properties.

=head2 Class->has_a(ParentClass => { ... }, ParentClass2 => { ...} )

Creates utility methods that map this object to parent Data::ObjectDriver objects.

Pass in a list of parent classes to map with a hash of parameters.  The following parameters
are recognized:

=over 4

=item * column

Name of the column(s) in this class to map with.  Pass in a single string if
the column is a singular key, an array ref if this is a composite key.

=item * method [OPTIONAL]

Name of the method to create in this class.  Defaults to the column name without
the _id suffix and with the suffix _obj appended.

=item * parent_method [OPTIONAL]

Name of the method created in the parent class.  Default is the lowercased 
name of the current class with the suffix _objs.

=item * cached [OPTIONAL]

If set to 1 then we will cache in-memory the resulting object inside this class.

=back

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

=head2 $obj->deflate

Returns a minimal representation of the object, for use in caches where
you might want to preserve space (like memcached). Can also be overridden
by subclasses to store the optimal representation of an object in the
cache. For example, if you have metadata attached to an object, you might
want to store that in the cache, as well.

=head2 $class->inflate($deflated)

Inflates the deflated representation of the object I<$deflated> into a
proper object in the class I<$class>.

=cut
