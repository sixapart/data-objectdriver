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

    $self->terms($param->{terms});
    $self->args($param->{args});
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

sub result_idx {
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

        $self->add_order([map { {column => $_} } @$pk]);
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
        $self->cursor(0);
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

1;
