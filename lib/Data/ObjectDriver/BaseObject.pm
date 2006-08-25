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
    my($props) = @_;
    {
        no strict 'refs'; ## no critic
        *{"${class}::__properties"} = sub { $props };
    }

    # predefine getter/setter methods here
    foreach my $col (@{ $props->{columns} }) {
        # Skip adding this method if the class overloads it.
        # this lets the SUPER::columnname magic do it's thing
        if (! $class->can($col)) {
            no strict 'refs'; ## no critic
            *{"${class}::$col"} = $class->column_func($col);
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
    my @args = @_;

    # Iterate over each remote object
    foreach my $config (@args) {
        my $parentclass = $config->{class};

        # Parameters
        my $column = $config->{column};
        my $method = $config->{method};
        my $cached = $config->{cached} || 0;
        my $parent_method = $config->{parent_method};

        # column is required
        if (!defined($column)) {
            die "Please specify a valid column for $parentclass"
        }

        # create a method name based on the column
        if (! defined $method) {
            if (!ref($column)) {
                $method = $column;
                $method =~ s/_id$//;
                $method .= "_obj";
            } elsif (ref($column) eq 'ARRAY') {
                foreach my $col (@{$column}) {
                    my $part = $col;
                    $part =~ s/_id$//;
                    $method .= $part . '_';
                }
                $method .= "obj";
            }
        }

        # die if we have clashing methods method
        if (! defined $method || defined(*{"${class}::$method"})) {
            die "Please define a valid method for $class->$column";
        }

        if ($cached) {
            # Store cached item inside this object's namespace
            my $cachekey = "__cache_$method";

            no strict 'refs'; ## no critic
            *{"${class}::$method"} = sub {
                my $obj = shift;

                return $obj->{$cachekey}
                    if defined $obj->{$cachekey};

                my $id = (ref($column) eq 'ARRAY')
                    ? [ map { $obj->{column_values}->{$_} } @{$column}]
                    : $obj->{column_values}->{$column}
                    ;
                ## Hold in a variable here too, so we don't lose it immediately
                ## by having only the weak reference.
                my $ret = $obj->{$cachekey} = $parentclass->lookup($id);
                weaken $obj->{$cachekey};
                return $ret;
            };
        } else {
            if (ref($column)) {
                no strict 'refs'; ## no critic
                *{"${class}::$method"} = sub {
                    my $obj = shift;
                    return $parentclass->lookup([ map{ $obj->{column_values}->{$_} } @{$column}]);
                };
            } else {
                no strict 'refs'; ## no critic
                *{"${class}::$method"} = sub {
                    return $parentclass->lookup(shift()->{column_values}->{$column});
                };
            }
        }

        # now add to the parent
        if (!defined $parent_method) {
            $parent_method = lc($class);
            $parent_method =~ s/^.*:://;

            $parent_method .= '_objs';
        }
        if (ref($column)) {
            no strict 'refs'; ## no critic
            *{"${parentclass}::$parent_method"} = sub {
                my $obj = shift;
                my $terms = shift || {};
                my $args = shift;

                my $primary_key = $obj->primary_key;

                # inject pk search into given terms.
                # composite key, ugh
                foreach my $key (@$column) {
                    $terms->{$key} = shift(@{$primary_key});
                }

                return $class->search($terms, $args);
            };
        } else {
            no strict 'refs'; ## no critic
            *{"${parentclass}::$parent_method"} = sub {
                my $obj = shift;
                my $terms = shift || {};
                my $args = shift;
                # TBD - use primary_key_to_terms
                $terms->{$column} = $obj->primary_key;
                return $class->search($terms, $args);
            };
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

sub new {
    my $obj = bless {}, shift;

    return $obj->init(@_);
}

sub init {
    my $self = shift;

    while (@_) {
        my $field = shift;
        my $val   = shift;
        $self->$field($val);
    }
    return $self;
}

sub is_pkless {
    my $obj = shift;
    my $prop_pk = $obj->properties->{primary_key};
    return 1 if ! $prop_pk;
    return 1 if ref $prop_pk eq 'ARRAY' && ! @$prop_pk;
}

sub is_primary_key {
    my $obj = shift;
    my($col) = @_;

    my $prop_pk = $obj->properties->{primary_key};
    if (ref($prop_pk)) {
        for my $pk (@$prop_pk) {
            return 1 if $pk eq $col;
        }
    } else {
        return 1 if $prop_pk eq $col;
    }

    return;
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
        $obj->$col($values->{$col});
    }
}

sub set_values_internal {
    my $obj = shift;
    my $values = shift;
    for my $col (keys %$values) {
        # Not needed for the internal version of this method
        #unless ( $obj->has_column($col) ) {
        #    Carp::croak("You tried to set inexistent column $col to value $values->{$col} on " . ref($obj));
        #}

        $obj->column_values->{$col} = $values->{$col};
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

sub column_values { $_[0]->{'column_values'} ||= {} }

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

    # set some values
    if (@_) {
        $obj->{column_values}->{$col} = shift;
        unless ($_[0] && ref($_[0]) eq 'HASH' && $_[0]->{no_changed_flag}) {
            $obj->{changed_cols}->{$col}++;
        }
    }

    $obj->{column_values}->{$col};
}

sub column_func {
    my $obj = shift;
    my $col = shift or die "Must specify column";

    return sub {
        my $obj = shift;
        # getter
        return $obj->{column_values}->{$col} unless (@_);

        # setter
        my ($val, $flags) = @_;
        $obj->{column_values}->{$col} = $val;
        unless (($val && ref($val) eq 'HASH' && $val->{no_changed_flag}) ||
                $flags->{no_changed_flag}) {
            $obj->{changed_cols}->{$col}++;
        }

        return $obj->{column_values}->{$col};
    };
}


sub changed_cols_and_pk {
    my $obj = shift;
    keys %{$obj->{changed_cols}};
}

sub changed_cols {
    my $obj = shift;
    my $pk = $obj->primary_key_tuple;
    my %pk = map { $_ => 1 } @$pk;
    grep !$pk{$_}, $obj->changed_cols_and_pk;
}

sub is_changed {
    my $obj = shift;
    if (@_) {
        return exists $obj->{changed_cols}->{$_[0]};
    } else {
        return $obj->changed_cols > 0;
    }
}

sub exists {
    my $obj = shift;
    return 0 unless $obj->has_primary_key;
    $obj->_proxy('exists', @_);
}

sub save {
    my $obj = shift;
    if ($obj->exists(@_)) {
        return $obj->update(@_);
    } else {
        return $obj->insert(@_);
    }
}

sub bulk_insert {
    my $class = shift;
    my $driver = $class->driver;

    return $driver->bulk_insert($class, @_);
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
    $obj->set_values($deflated->{columns});
    $obj->{changed_cols} = {};
    $obj;
}

sub DESTROY { }

sub AUTOLOAD {
    my $obj = $_[0];
    (my $col = our $AUTOLOAD) =~ s!.+::!!;
    Carp::croak("Cannot find method '$col' for class '$obj'") unless ref $obj;
    unless ($obj->has_column($col)) {
        Carp::croak("Cannot find column '$col' for class '" . ref($obj) . "'");
    }

    {
        no strict 'refs'; ## no critic
        *$AUTOLOAD = $obj->column_func($col);
    }

    goto &$AUTOLOAD;
}

sub has_partitions {
    my $class = shift;
    my(%param) = @_;
    my $how_many = delete $param{number}
        or Carp::croak("number (of partitions) is required");

    ## Save the get_driver subref that we were passed, so that the
    ## SimplePartition driver can access it.
    $class->properties->{partition_get_driver} = delete $param{get_driver}
        or Carp::croak("get_driver is required");

    ## When creating a new $class object, we should automatically fill in
    ## the partition ID by selecting one at random, unless a partition_id
    ## is already defined. This allows us to keep it simple but for the
    ## caller to do something more complex, if it wants to.
    $class->add_trigger(pre_insert => sub {
        my($obj, $orig_obj) = @_;
        unless (defined $obj->partition_id) {
            my $partition_id = int(rand $how_many) + 1;
            $obj->partition_id($partition_id);
            $orig_obj->partition_id($partition_id);
        }
    });
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

=head2 Class->install_properties(\%params)

Defines all the properties of the specified object class. Generally you should
call C<install_properties()> in the body of your class definition, so the
properties can be set when the class is C<use>d or C<require>d.

Required members of C<%params> are:

=over 4

=item * C<columns>

All the columns in the object class. This property is an arrayref.

=item * C<primary_key>

The column or columns used to uniquely identify an instance of the object
class. If one column (such as a simple numeric ID) identifies the class,
C<primary_key> should be a scalar. Otherwise, C<primary_key> is an arrayref.

=item * C<datasource>

The identifier of the table in which the object class's data are stored.
Usually the datasource is simply the table name, but the datasource can be
decorated into the table name by the C<Data::ObjectDriver::DBD> module if the
database requires special formatting of table names.

=item * C<driver> or C<get_driver>

The driver used to perform database operations (lookup, update, etc) for the
object class.

C<driver> is the instance of C<Data::ObjectDriver> to use. If your driver
requires configuration options not available when the properties are initially
set, specify a coderef as C<get_driver> instead. It will be called the first
time the driver is needed, storing the driver in the class's C<driver> property
for subsequent calls.

=back

The optional members of C<%params> are:

=over 4

=item * C<column_defs>

Specifies types for specially typed columns, if any, as a hashref. For example,
if a column holds a timestamp, name it in C<column_defs> as a C<date> for
proper handling with some C<Data::ObjectDriver::Driver::DBD> database drivers.
Columns for which types aren't specified are handled as C<char> columns.

Known C<column_defs> types are:

=over 4

=item * C<blob>

A blob of binary data. C<Data::ObjectDriver::Driver::DBD::Pg> maps this to
C<DBI::Pg::PG_BYTEA>, and C<DBD::SQLite> to C<DBI::SQL_BLOB>.

=item * C<bin_char>

A non-blob string of binary data. C<Data::ObjectDriver::Driver::DBD::SQLite>
maps this to C<DBI::SQL_BINARY>.

=back

Other types may be defined by custom database drivers as needed, so consult
their documentation.

=item * C<db>

The name of the database. When used with C<Data::ObjectDriver::Driver::DBI>
type object drivers, this name is passed to the C<init_db> method when the
actual database handle is being created.

=back

Custom object drivers may define other properties for your object classes.
Consult the documentation of those object drivers for more information.

=head2 Class->properties

Returns the named object class's properties as a hashref. Note some of the
standard object class properties, such as C<primary_key>, have more convenient
accessors than reading the properties directly.

=head2 Class->has_a(ParentClass => { ... }, ParentClass2 => { ...} )

Creates utility methods that map this object to parent Data::ObjectDriver objects.

Pass in a list of parent classes to map with a hash of parameters.  The following parameters
are recognized:

=over 4

=item * column

Name of the column(s) in this class to map with.  Pass in a single string if
the column is a singular key, an array ref if this is a composite key.

   column => 'user_id'
   column => ['user_id', 'photo_id']

=item * method [OPTIONAL]

Name of the method to create in this class.  Defaults to the column name(s) without
the _id suffix and with the suffix _obj appended.

=item * parent_method [OPTIONAL]

Name of the method created in the parent class.  Default is the lowercased
name of the current class with the suffix _objs.

=item * cached [OPTIONAL]

If set to 1 cache the result of the fetching the parent object in the current class.  Note
that this is a private copy to this class only, and does not interact with other caches
in the system.

=back

B<NOTE:> C<has_a> is an experimental system, likely to be both buggy and change
in future versions.

=head2 column_func

This method is called to get/set column values.  Subclasses can override this and get different
behavior.

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
