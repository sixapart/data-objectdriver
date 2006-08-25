# $Id$

package Data::ObjectDriver::SQL;
use strict;
use warnings;

use base qw( Class::Accessor::Fast );

__PACKAGE__->mk_accessors(qw( select select_map select_map_reverse from joins where bind limit offset group order having where_values ));

sub new {
    my $class = shift;
    my $stmt = $class->SUPER::new(@_);
    $stmt->select([]);
    $stmt->select_map({});
    $stmt->select_map_reverse({});
    $stmt->bind([]);
    $stmt->from([]);
    $stmt->where([]);
    $stmt->where_values({});
    $stmt->having([]);
    $stmt->joins([]);
    $stmt;
}

sub add_select {
    my $stmt = shift;
    my($term, $col) = @_;
    push @{ $stmt->select }, $term;
    $stmt->select_map->{$term} = $col;
    $stmt->select_map_reverse->{$col} = $term;
}

sub add_join {
    my $stmt = shift;
    my($table, $joins) = @_;
    push @{ $stmt->joins }, {
        table => $table,
        joins => ref($joins) eq 'ARRAY' ? $joins : [ $joins ],
    };
}

sub as_sql {
    my $stmt = shift;
    my $sql = '';
    if (@{ $stmt->select }) {
        $sql .= 'SELECT ';
        $sql .= join(', ',  map {
            my $alias = $stmt->select_map->{$_};
            $alias && /(?:^|\.)\Q$alias\E$/ ? $_ : "$_ $alias";
        } @{ $stmt->select }) . "\n";
    }
    $sql .= 'FROM ';
    ## Add any explicit JOIN statements before the non-joined tables.
    if ($stmt->joins && @{ $stmt->joins }) {
        for my $j (@{ $stmt->joins }) {
            my($table, $joins) = map { $j->{$_} } qw( table joins );
            $sql .= $table;
            for my $join (@{ $j->{joins} }) {
                $sql .= ' ' .
                        uc($join->{type}) . ' JOIN ' . $join->{table} . ' ON ' .
                        $join->{condition};
            }
        }
        $sql .= ', ' if @{ $stmt->from };
    }
    $sql .= join(', ', @{ $stmt->from }) . "\n";
    $sql .= $stmt->as_sql_where;

    $sql .= $stmt->as_aggregate('group');
    $sql .= $stmt->as_sql_having;
    $sql .= $stmt->as_aggregate('order');

    $sql .= $stmt->as_limit;
    $sql;
}

sub as_limit {
    my $stmt = shift;
    my $n = $stmt->limit or
        return '';
    die "Non-numerics in limit clause ($n)" if $n =~ /\D/;
    return sprintf "LIMIT %d%s\n", $n,
           ($stmt->offset ? " OFFSET " . int($stmt->offset) : "");
}

sub as_aggregate {
    my $stmt = shift;
    my($set) = @_;

    if (my $attribute = $stmt->$set()) {
        my $elements = (ref($attribute) eq 'ARRAY') ? $attribute : [ $attribute ];
        return uc($set) . ' BY '
            . join(', ', map { $_->{column} . ($_->{desc} ? (' ' . $_->{desc}) : '') } @$elements)
                . "\n";
    }

    return '';
}

sub as_sql_where {
    my $stmt = shift;
    $stmt->where && @{ $stmt->where } ?
        'WHERE ' . join(' AND ', @{ $stmt->where }) . "\n" :
        '';
}

sub as_sql_having {
    my $stmt = shift;
    $stmt->having && @{ $stmt->having } ?
        'HAVING ' . join(' AND ', @{ $stmt->having }) . "\n" :
        '';
}

sub add_where {
    my $stmt = shift;
    ## xxx Need to support old range and transform behaviors.
    my($col, $val) = @_;
    Carp::croak("Invalid/unsafe column name $col") unless $col =~ /^[\w\.]+$/;
    my($term, $bind) = $stmt->_mk_term($col, $val);
    push @{ $stmt->{where} }, "($term)";
    push @{ $stmt->{bind} }, @$bind;
    $stmt->where_values->{$col} = $val;
}

sub has_where {
    my $stmt = shift;
    my($col, $val) = @_;

    # TODO: should check if the value is same with $val?
    exists $stmt->where_values->{$col};
}

sub add_having {
    my $stmt = shift;
    my($col, $val) = @_;
#    Carp::croak("Invalid/unsafe column name $col") unless $col =~ /^[\w\.]+$/;

    if (my $orig = $stmt->select_map_reverse->{$col}) {
        $col = $orig;
    }

    my($term, $bind) = $stmt->_mk_term($col, $val);
    push @{ $stmt->{having} }, "($term)";
    push @{ $stmt->{bind} }, @$bind;
}

sub _mk_term {
    my $stmt = shift;
    my($col, $val) = @_;
    my $term = '';
    my @bind;
    if (ref($val) eq 'ARRAY') {
        if (ref $val->[0] or $val->[0] eq '-and') {
            my $logic = 'OR';
            my @values = @$val;
            if ($val->[0] eq '-and') {
                $logic = 'AND';
                shift @values;
            }

            my @terms;
            for my $v (@values) {
                my($term, $bind) = $stmt->_mk_term($col, $v);
                push @terms, $term;
                push @bind, @$bind;
            }
            $term = join " $logic ", @terms;
        } else {
            $term = "$col IN (".join(',', ('?') x scalar @$val).')';
            @bind = @$val;
        }
    } elsif (ref($val) eq 'HASH') {
        $term = "$col $val->{op} ?";
        push @bind, $val->{value};
    } elsif (ref($val) eq 'SCALAR') {
        $term = "$col $$val";
    } else {
        $term = "$col = ?";
        push @bind, $val;
    }
    ($term, \@bind);
}

1;

__END__

=head1 NAME

Data::ObjectDriver::SQL - an SQL statement

=head1 SYNOPSIS

    my $sql = Data::ObjectDriver::SQL->new();
    $sql->select([ 'id', 'name', 'bucket_id', 'note_id' ]);
    $sql->from([ 'foo' ]);
    $sql->add_where('name',      'fred');
    $sql->add_where('bucket_id', { op => '!=', value => 47 });
    $sql->add_where('note_id',   \'IS NULL');
    $sql->limit(1);

    my $sth = $dbh->prepare($sql->as_sql);
    $sth->execute(@{ $sql->{bind} });
    my @values = $sth->selectrow_array();
    
    my $obj = SomeObject->new();
    $obj->set_columns(...);

=head1 DESCRIPTION

I<Data::ObjectDriver::SQL> represents an SQL statement. SQL statements are used
internally to C<Data::ObjectDriver::Driver::DBI> object drivers to convert
database operations (C<search()>, C<update()>, etc) into database operations,
but sometimes you just gotta use SQL.

=head1 USAGE

=head2 C<Data::ObjectDriver::SQL-E<gt>new()>

Creates a new, empty SQL statement.

=head2 C<$sql-E<gt>select()>

=head2 C<$sql-E<gt>select(\@columns)>

Returns or sets the database columns to select in a C<SELECT> query.

=head2 select_map

=head2 select_map_reverse

=head2 C<$sql-E<gt>from()>

=head2 C<$sql-E<gt>from(\@tables)>

Returns or sets the tables used in the query.

Note if you perform a C<SELECT> query with multiple tables, the rows will be
selected as Cartesian products that you'll need to reduce with C<WHERE>
clauses. Your query might be better served using a real query specified through
the C<joins> member of your statement.

=head2 joins

=head2 where

=head2 bind

=head2 C<$sql-E<gt>limit()>

=head2 C<$sql-E<gt>limit($limit)>

Returns or sets a C<SELECT> query's maximum number of records to return.

=head2 C<$sql-E<gt>offset()>

=head2 C<$sql-E<gt>offset($offset)>

Returns or sets a C<SELECT> query's number of records to skip in this query.
Combined with a C<limit> and logic to increase the offset, you can use multiple
queries to paginate a set of records with a moving window of C<limit> records.

=head2 C<$sql-E<gt>group()>

=head2 C<$sql-E<gt>group(\%field)>

=head2 C<$sql-E<gt>group(\@fields)>

Returns or sets the fields on which to group the results. Grouping fields are
hashrefs containing these members:

=over 4

=item * C<column>

Name of the column on which to group.

=back

Note you can set a single grouping field, or use an arrayref containing multiple
grouping fields.

=head2 C<$sql-E<gt>having()>

=head2 C<$sql-E<gt>having(\@clauses)>

Returns or sets the list of clauses to specify in the C<HAVING> portion of the
C<GROUP ... HAVING> clause. Individual clauses are simple strings containing
the expression to use.

Consider using the C<add_having> method instead of adding C<HAVING> clauses
directly.

=head2 C<$sql-E<gt>order()>

=head2 C<$sql-E<gt>order(\%field)>

=head2 C<$sql-E<gt>order(\@fields)>

Returns or sets the fields by which to order the results. Ordering fields are hashrefs containing these members:

=over 4

=item * C<column>

Name of the column by which to order.

=item * C<desc>

The SQL keyword to use to specify the ordering. For example, use C<DESC> to
specify a descending order. This member is optional.

=back

Note you can set a single ordering field, or use an arrayref containing
multiple ordering fields.

=head2 where_values

=head1 DIAGNOSTICS

=head1 BUGS AND LIMITATIONS

I<Data::ObjectDriver::SQL> does not provide the functionality for turning SQL
statements into instances of object classes.

=head1 SEE ALSO

=head1 LICENSE

I<Data::ObjectDriver> is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR & COPYRIGHT

Except where otherwise noted, I<Data::ObjectDriver> is Copyright 2005-2006
Six Apart, cpan@sixapart.com. All rights reserved.

=cut

