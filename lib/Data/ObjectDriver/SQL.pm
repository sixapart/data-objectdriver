# $Id$

package Data::ObjectDriver::SQL;
use strict;
use base qw( Class::Accessor::Fast );

__PACKAGE__->mk_accessors(qw( from join where bind limit offset order ));

sub new {
    my $class = shift;
    my $stmt = $class->SUPER::new(@_);
    $stmt->bind([]);
    $stmt->from([]);
    $stmt->where([]);
    $stmt;
}

sub as_sql {
    my $stmt = shift;
    my $sql = 'FROM ';
    if (my $join = $stmt->join) {
        ## If there's an actual JOIN statement, assume it's for joining with
        ## the main datasource for the object we're loading. So shift that
        ## off of the FROM list, and write the JOIN statement and condition.
        $sql .= shift(@{ $stmt->from }) . ' ' .
                uc($join->{type}) . ' JOIN ' . $join->{table} . ' ON ' .
                $join->{condition};
        $sql .= ', ' if @{ $stmt->from };
    }
    $sql .= join(', ', @{ $stmt->from }) . "\n";
    $sql .= $stmt->as_sql_where;
    if (my $order = $stmt->order) {
        $sql .= 'ORDER BY ' . $order->{column} . ' ' . $order->{desc} . "\n";
    }
    if (my $n = $stmt->limit) {
        $n =~ s/\D//g;   ## Get rid of any non-numerics.
        $sql .= sprintf "LIMIT %d%s\n", $n,
            ($stmt->offset ? " OFFSET " . $stmt->offset : "");
    }
    $sql;
}

sub as_sql_where {
    my $stmt = shift;
    $stmt->where && @{ $stmt->where } ?
        'WHERE ' . join(' AND ', @{ $stmt->where }) . "\n" :
        '';
}

sub add_where {
    my $stmt = shift;
    ## xxx Need to support old range and transform behaviors.
    my($col, $val) = @_;
    Carp::croak("Invalid/unsafe column name $col") unless $col =~ /^[\w\.]+$/;
    my($term, $bind) = _mk_term($col, $val);
    push @{ $stmt->{where} }, "($term)";
    push @{ $stmt->{bind} }, @$bind;
}

sub _mk_term {
    my($col, $val) = @_;
    my $term = '';
    my @bind;
    if (ref($val) eq 'ARRAY') {
        my $logic = 'OR';
        if ($val->[0] eq '-and') {
            $logic = 'AND';
            shift @$val;
        }
        my @terms;
        for my $val (@$val) {
            my($term, $bind) = _mk_term($col, $val);
            push @terms, $term;
            push @bind, @$bind;
        }
        $term = join " $logic ", @terms;
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
