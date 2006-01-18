# $Id$

package Data::ObjectDriver::SQL;
use strict;
use base qw( Class::Accessor::Fast );

__PACKAGE__->mk_accessors(qw( select select_map from join where bind limit offset group order ));

sub new {
    my $class = shift;
    my $stmt = $class->SUPER::new(@_);
    $stmt->select([]);
    $stmt->select_map({});
    $stmt->bind([]);
    $stmt->from([]);
    $stmt->where([]);
    $stmt;
}

sub add_select {
    my $stmt = shift;
    my($term, $col) = @_;
    push @{ $stmt->select }, $term;
    $stmt->select_map->{$term} = $col;
}

sub as_sql {
    my $stmt = shift;
    my $sql = '';
    if (@{ $stmt->select }) {
        $sql .= 'SELECT ';
        $sql .= join(', ', @{ $stmt->select }) . "\n";
    }
    $sql .= 'FROM ';
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
    for my $set (qw( group order )) {
        if (my $attribute = $stmt->$set()) {
            my $elements = (ref($attribute) eq 'ARRAY') ? $attribute : [ $attribute ];
            $sql .= uc($set) . ' BY '
                . join(', ', map { $_->{column} . ($_->{desc} ? (' ' . $_->{desc}) : '') } @$elements)
                . "\n";
        }
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
    my($term, $bind) = $stmt->_mk_term($col, $val);
    push @{ $stmt->{where} }, "($term)";
    push @{ $stmt->{bind} }, @$bind;
}

sub _mk_term {
    my $stmt = shift;
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
            my($term, $bind) = $stmt->_mk_term($col, $val);
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
