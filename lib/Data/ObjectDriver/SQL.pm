# $Id$

package Data::ObjectDriver::SQL;
use strict;
use warnings;

use base qw( Class::Accessor::Fast );

__PACKAGE__->mk_accessors(qw( select select_map select_map_reverse from join where bind limit offset group order having where_values ));

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
    $stmt;
}

sub add_select {
    my $stmt = shift;
    my($term, $col) = @_;
    push @{ $stmt->select }, $term;
    $stmt->select_map->{$term} = $col;
    $stmt->select_map_reverse->{$col} = $term;
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
    if (my $join = $stmt->join) {
        ## If there's an actual JOIN statement, assume it's for joining with
        ## the main datasource for the object we're loading. So shift that
        ## off of the FROM list, and write the JOIN statement and condition.
        $sql .= shift(@{ $stmt->from });

        my @joins = ref($join) eq 'ARRAY' ? @$join : ($join);
        for my $j (@joins) {
            $sql .= ' ' .
                    uc($j->{type}) . ' JOIN ' . $j->{table} . ' ON ' .
                    $j->{condition};
        }

        $sql .= ', ' if @{ $stmt->from };
    }
    $sql .= join(', ', @{ $stmt->from }) . "\n";
    $sql .= $stmt->as_sql_where;

    $sql .= $stmt->as_aggregate('group');
    $sql .= $stmt->as_sql_having;
    $sql .= $stmt->as_aggregate('order');

    if (my $n = $stmt->limit) {
        $n =~ s/\D//g;   ## Get rid of any non-numerics.
        $sql .= sprintf "LIMIT %d%s\n", $n,
            ($stmt->offset ? " OFFSET " . $stmt->offset : "");
    }
    $sql;
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
