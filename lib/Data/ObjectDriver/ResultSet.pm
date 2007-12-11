package Data::ObjectDriver::ResultSet;

use strict;

use base qw( Class::Accessor::Fast );

__PACKAGE__->mk_accessors(qw(class
                             terms
                             args

                             page_size
                             paging
                             no_paging
                             page

                             cursor
                             results
                             cached_count

                             is_finished ));

use constant DEF_PAGE_SIZE => 500;

sub new {
    my $class = shift;
    my ($param) = @_;
    my $self = bless {}, ref $class || $class;

    $self->class($param->{class});
    $self->page_size($param->{page_size} || DEF_PAGE_SIZE);
    $self->paging($param->{no_paging} ? 0 : 1);

    # We automatically set 'paging' when a limit term is cleared, so make sure
    # we know if the user originally wanted paging turned off
    $self->no_paging($param->{no_paging});

    $self->is_finished(0);
    $self->add_constraint($param->{terms}, $param->{args});

    $self->cursor(-1);

    return $self;
}

sub iterator {
    my $class = shift;
    my ($objs) = @_;

    my $self = bless {}, ref $class || $class;
    $self->results($objs);
    $self->cursor(-1);
    $self->paging(0);
    $self->is_finished(0);

    return $self;
}

sub disable_paging { shift->paging(0) }
sub enable_paging  { shift->paging(1) }

sub add_constraint {
    my $self = shift;
    my ($terms, $args) = @_;

    if ($terms) {
        die "First argument to 'add_constraint' must be a hash reference"
          if ref $terms ne 'HASH';

        my $cur_terms = $self->terms || {};
        foreach my $k (keys %$terms) {
            $cur_terms->{$k} = $terms->{$k};
        }
        $self->terms($cur_terms);
    }

    if ($args) {
        die "Second argument to 'add_constraint' must be a hash reference"
          if ref $args ne 'HASH';

        my $cur_args = $self->args || {};
        foreach my $k (keys %$args) {
            $cur_args->{$k} = $args->{$k};

            # Turn off paging if we get a limit term
            $self->paging(0) if $k eq 'limit';
        }
        $self->args($cur_args);
    }

    return 1;
}

sub clear_constraint {
    my $self = shift;
    my ($term_names, $arg_names) = @_;

    my $terms = $self->terms;
    if ($term_names and $terms) {
        die "First argument to 'clear_constraint' must be an array reference"
          if ref $term_names ne 'ARRAY';

        foreach my $n (@$term_names) {
            delete $terms->{$n};
        }
    }

    my $args = $self->args;
    if ($arg_names and $args) {
        die "Second argument to 'clear_constraint' must be an array reference"
          if ref $arg_names ne 'ARRAY';

        foreach my $n (@$arg_names) {
            delete $args->{$n};

            # Turn on paging if we clear a limit term unless the user explicitly
            # said they didn't want any paging
            $self->paging(1) if ($n eq 'limit') and not $self->no_paging;
        }
    }

    return 1;
}

sub add_term        { shift->add_constraint($_[0])                    }
sub clear_term      { shift->clear_constraint(\@_)                    }

sub add_limit       { shift->add_constraint(undef, {limit => $_[0]})  }
sub clear_limit     { shift->clear_constraint(undef, ['limit'])       }

sub add_offset      { shift->add_constraint(undef, {offset => $_[0]}) }
sub clear_offset    { shift->clear_constraint(undef, ['offset'])      }

sub add_order       { shift->add_constraint(undef, {sort => $_[0]}) }
sub clear_order     { shift->clear_constraint(undef, ['sort'])       }

sub index {
    my $self = shift;

    return ($self->page_size * $self->page) + $self->cursor;
}

sub load_results {
    my $self = shift;

    if ($self->paging) {
        # Set limit directly as to not trigger the 'turn paging off' code
        my $args = $self->args || {};
        $args->{limit} = $self->page_size;
        $self->args($args);

        $self->add_offset($self->page * $self->page_size);

        my $pk = $self->class->properties->{primary_key};
        $pk = [$pk] unless ref $pk;

        $self->add_order([map { {column => $_} } @$pk]) unless $args->{sort};
    }

    my @r = $self->class->search($self->terms, $self->args);
    $self->results(\@r);

    return \@r;
}

sub next {
    my $self = shift;

    return if $self->is_finished;

    $self->cursor($self->cursor + 1);

    # Boundary check
    if ($self->paging and ($self->cursor >= $self->page_size)) {
        $self->page($self->page + 1);
        $self->cursor(-1);
        $self->results(undef);
    }

    # Load the results and return an object
    my $results = $self->results || $self->load_results;

    my $obj = $results->[$self->cursor];

    if ($obj) {
        return $obj;
    } else {
        $self->is_finished(1);
        return;
    }
}

sub prev {
    my $self = shift;

    $self->cursor($self->cursor - 1);

    # Boundary check
    if ($self->cursor == -1) {
        # If we can, go back a page
        if ($self->paging and ($self->page > 0)) {
            $self->page($self->page - 1);
            $self->cursor($self->page_size - 1);
            $self->results(undef);
        } else {
            return;
        }
    }

    # Load the results and return an object
    my $results = $self->results || $self->load_results;

    my $obj = $results->[$self->cursor];
    if ($obj) {
        return $obj;
    } else {
        return;
    }
}

sub curr {
    my $self = shift;

    return $self->results->[$self->cursor];
}

sub slice {
    my $self = shift;
    my ($start, $end) = @_;
    my $limit = $end - $start;

    # Do we already have results?
    if ($self->results) {
        if ($self->paging) {
            my $cur_start = $self->page * $self->page_size;
            my $cur_end   = ($self->page+1) * $self->page_size;

            # See if this slice is in the results we already have
            if (($start >= $cur_start) and ($end < $cur_end)) {
                $start -= $cur_start;
            }
        } else {
            return @{ $self->results }[$start, $end];
        }
    }

    $self->add_offset($start);
    $self->add_limit($limit);

    my $r = $self->load_results;

    return wantarray ? @$r : $r;
}

sub count {
    my $self = shift;
    my $c;

    return $self->cached_count if defined $self->cached_count;

    # If we're not paging and we already have results, we already know the count
    if (not $self->paging and $self->results) {
        $c = scalar @{ $self->results };
    }

    $c = $self->class->count($self->terms, $self->args) || 0;

    $self->cached_count($c);

    return $c;
}

sub first {
    my $self = shift;

    # Clear is finished in case they are comming back from the last element
    $self->is_finished(0);

    $self->cursor(0);

    if ($self->paging) {
        if ($self->page > 0) {
            $self->page(0);
            $self->results(undef);
        }
    }

    my $results = $self->results || $self->load_results;

    my $obj = $results->[$self->cursor];
    if ($obj) {
        return $obj;
    } else {
        return;
    }
}

sub last {
    my $self = shift;
    my $results;

    if ($self->paging) {
        # Figure out what the last page is
        my $last_page = int($self->count/$self->page_size);

        if ($last_page > $self->page) {
            $self->page($last_page);
            $self->results(undef);
        }
    }

    $results = $self->results || $self->load_results;
    $self->cursor($#$results);

    return $results->[$self->cursor];
}

sub is_last {
    my $self = shift;
    my $results = $self->results || $self->load_results;
    return (scalar @{$results} == $self->cursor + 1) ? 1 : 0;
}

1;

__END__

=pod

=head1 NAME

Data::ObjectDriver::ResultSet - Manage a DB query

=head1 SYNOPSIS

    # Get a resultset object for Object::Widget, which inherits from
    # Data::ObjectDriver::BaseObject
    my $result = Object::Widget->result($terms, $args);

    $result->add_term({color => 'blue'});

    $result->add_limit(10);
    $result->add_offset(100);

    while (not $result->is_empty) {
        my $widget = $result->next;

        # Do stuff with $widget
    }

=head1 DESCRIPTION

This object is returned by the 'result' method found in the L<Data::ObjectDriver::BaseObject> class.  This object manages a query and the resulting data.  It
allows additional search terms and arguments to be added and will not submit the
query until a method that returns data is called.  By passing this object around
code in multiple places can alter the query easily until the data is needed.

Once a method returning data is called (L<next>, L<count>, etc) the query is
submitted to the database and the returned data is managed by the ResultSet
object like an iterator.

=head1 METHODS

=head2 $result_set = $class->result($terms, $args)

This method is actually defined in L<Data::ObjectDriver::BaseObject> but it is
the way a new ResultSet object is created.

Arguments:

=over 4

=item I<$terms> - A hashref.  Same format as the first argument to Data::ObjectDriver::DBI::search

=item I<$args> - A hashref.  Same format as the second argument to Data::ObjectDriver::DBI::search with the addition of the following keys:

=over 4

=item 'page_size' - The size of the pages retrieved.  Default I<500>

=item 'no_paging' - Turn off internal paging

=back

=back

Return value:

This method returns a Data::ObjectDriver::ResultSet object

=head2 $new_result = Data::ObjectDriver::ResultSet->iterator(\@data)

Create a new result set object that takes existing data and operates only as an
iterator, without any of the query managment.

Arguments:

=over 4

=item $data - An array ref of data elements

=back

Return value:

A L<Data::ObjectDriver::ResultSet> object

=head2 $num = $result->page_size($num)

Set the internal page size used when retrieving results from the DB.  The caller does not have to manage pages, this is only to keep an upper bound on the amount of memory and time taken to pull objects from potentially large datasets.  The

Arguments:

=over 4

=item $num - A scalar integer giving the number of pages. Default I<500>

=back

; Return Value
: Returns the page size

; Notes
: I<None>

; Example

  $res->page_size(1_000)

=head2 disable_paging

Turn off internal paging.  There is no normal usage situation where this is necessary.

Arguments:

=over 4

=item I<none>

=back

; Return Value
: A true value

; Notes
: I<None>

; Example

  $res->disable_paging

=head2 enable_paging

Turn on internal paging.  By default paging is on.  This method is only here to compliment I<disable_paging>.

Arguments:

=over 4

=item I<none>

=back

; Return Value
: A true value

; Notes
: I<None>

; Example

  $res->enable_paging

=head2 add_constraint

Apply a constraint to the result.  The format of the two arguments is the same as for Data::ObjectDriver::DBI::search

Arguments:

=over 4

=item $terms - A hashref of object fields and values constraining them.  Same as first parameter to I<result> method.

=item $args - A hashref of values that affect the returned data, such as limit and sort by.  Same as first parameter to I<result> method.

=back

; Return value
: Returns I<1> if successful and I<0> otherwise

; Notes
: Do we fail if called after we've retrieved the result set?  Ignore it?  Requery?

; Example

  $res->add_constraint({object_id => $id}, {limit => 100})

=head2 add_term

Apply a single search term to the result.  Equivalent to:

  $res->add_constraint($terms)

Arguments:

=over 4

=item $terms - A hashref of object fields and values constraining them

=back

; Return value
: Returns I<1> if successful and I<0> otherwise

; Notes
: Same question as for I<add_constraint>

; Example

  $res->add_term({object_id => $id})

=head2 clear_term

Clear a single search term from the result.

Arguments:

=over 4

=item @terms - An array of term names to clear

=back

; Return value
: Returns I<1> if successful and I<0> otherwise

; Notes
: I<none>

; Example

  $res->clear_term(qw(limit offset))

=head2 add_limit

Apply a limit to the result.  Equivalent to:

  $res->add_constraint({}, {limit => $limit})

Arguments:

=over 4

=item $limit - A scalar numeric value giving the limit of the number of objects returned

=back

; Return value
: Returns I<1> if successful and I<0> otherwise

; Notes
:

; Example

  $res->add_limit(100)

=head2 clear_limit

Clear any limit value in the result.

Arguments:

=over 4

=item I<none>

=back

; Return value
: Returns I<1> if successful and I<0> otherwise

; Notes
: I<None>

; Example

  $res->clear_limit

=head2 add_offset

Add an offset for the results returned.  Result set must also have a limit set at some point.

Arguments:

=over 4

=item $offset - A scalar numeric value giving the offset for the first object returned

=back

; Return value
: Returns I<1> if successful and I<0> otherwise

; Notes
: I<none>

; Example

  $res->add_offset(5_000)

=head2 clear_offset

Clear any offset value in the result.

Arguments:

=over 4

=item I<none>

=back

; Return value
: Returns I<1> if successful and I<0> otherwise

; Notes
:

; Example

  $res->clear_offset

=head2 add_order

Add a sort order for the results returned.

Arguments:

=over 4

=item [0] = $order = I< - A scalar string value giving the sort order for the results, one of I<ascend> or I<descend>

=back

; Return value
: Returns I<1> if successful and I<0> otherwise

; Notes
: >none''

; Example

  $res->add_order('ascend')

=head2 clear_order

Clear any offset value in the result.

Arguments:

=over 4

=item I<none>

=back

; Return value
: Returns I<1> if successful and I<0> otherwise

; Notes
: I<none>

; Example

  $res->clear_order

=head2 index

Return the current index into the result set.

Arguments:

=over 4

=item I<none>

=back

; Return value
: An integer giving the zero based index of the current element in the result set.

; Notes
: I<none>

; Example

  $idx = $res->index;

=head2 next

Retrieve the next item in the resultset

Arguments:

=over 4

=item I<none>

=back

; Return value
: The next object or undef if past the end of the result set

; Notes
: Calling this method will force a DB query.  All subsequent calls to I<curr> will return this object

; Example

  $obj = $res->next;

=head2 prev

Retrieve the previous item in the result set

Arguments:

=over 4

=item I<none>

=back

; Return value
: The previous object or undef if before the beginning of the result set

; Notes
: All subsequent calls to I<curr> will return this object

; Example

  $obj = $res->prev;

=head2 curr

Retrieve the current item in the result set.  This item is set by calls to I<next> and I<prev>

Arguments:

=over 4

=item I<none>

=back

; Return value
: The current object or undef if past the boundaries of the result set

; Notes
: I<none>

; Example

  $obj = $res->curr

=head2 slice

Return a slice of the result set.  This is logically equivalent to setting a limit and offset and then retrieving all the objects via I<->next>.  If you call I<slice> and then call I<next>, you will get I<undef> and additionally I<is_empty> will be true.

Arguments:

=over 4

=item $from - Scalar integer giving the start of the slice range

=item $to - Scalar integer giving the end of the slice range

=back

; Return value
: An array of objects

; Notes
: Objects are index from 0 just like perl arrays.

; Example

  my @objs = $res->slice(0, 20)

=head2 count

Get the count of the items in the result set.

Arguments:

=over 4

=item I<none>

=back

; Return value
: A scalar count of the number of items in the result set

; Notes
: This will cause a count() query on the database if the result set hasn't been retrieved yet.  If the result set has been retrieved it will just return the number of objects stored in the result set object.

; Example

  $num = $res->count

=head2 is_finished

Returns whether we've arrived at the end of the result set

Arguments:

=over 4

=item I<none>

=back

; Return value
: Returns I<1> if we are finished iterating though the result set and I<0> otherwise

; Notes
: I<none>

; Example

  while (not $res->is_finished) {
      my $obj = $res->next;
      # Stuff ...
  }

=head2 first

Returns the first object in the result set.

Arguments:

=over 4

=item I<none>

=back

; Return value
: The first object in the result set

; Notes
: Resets the current cursor so that calls to I<curr> return this value.

; Example

  $obj = $res->first

=head2 last

Returns the last object in the result set.

Arguments:

=over 4

=item I<none>

=back

; Return value
: The last object in the result set

; Notes
: Resets the current cursor so that calls to I<curr> return this value.

; Example

  $obj = $res->last

=head2 is_last

Returns 1 if the cursor is on the last row of the result set, 0 if it is not.

Arguments:

=over 4

=item I<none>

=back

; Return value
: Returns I<1> if the cursor is on the last row of the result set, I<0> if it is not.

; Example

  if ( $res->is_last ) {
     ## do some stuff
  }

=cut

