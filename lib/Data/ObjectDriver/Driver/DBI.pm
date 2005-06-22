# $Id$

package Data::ObjectDriver::Driver::DBI;
use strict;
use base qw( Data::ObjectDriver Class::Accessor::Fast );

use DBI;

__PACKAGE__->mk_accessors(qw( dsn username password dbh ));

sub init {
    my $driver = shift;
    my %param = @_;
    for my $key (keys %param) {
        $driver->$key($param{$key});
    }
    ## Rebless the driver into the DSN-specific subclass (e.g. "mysql").
    my($type) = lc($driver->dsn) =~ /^dbi:(\w*)/;
    my $class = __PACKAGE__ . '::' . $type;
    eval "use $class";
    die $@ if $@;
    bless $driver, $class;
    $driver;
}

# Base methods, override in driver
sub generate_pk {
    my $driver = shift;
    if (my $generator = $driver->pk_generator) {
        return $generator->(@_);
    }
}
sub fetch_id { undef }
sub offset_implemented { 1 }

# map to true DB column, for databases that can't store long identifiers :(
sub db_column_name {
    my ($driver, $table, $column) = @_; 
    return $column;
}

# Override in DB Driver to pass correct attributes to bind_param call
sub bind_param_attributes { return undef }

# set to 1 during development to get sql statements in the error log
use constant SQLDEBUG => 0;

sub rw_handle {
    my $driver = shift;
    my $db = shift || 'main';
    my $dbh = $driver->dbh;
    unless ($dbh) {
        $dbh = $driver->init_db($db) or die $driver->errstr;
        $driver->dbh($dbh);
    }
    $dbh;
}
*r_handle = \&rw_handle;

sub search {
    my $driver = shift;
    my($class, $terms, $args) = @_;

    my $stmt = $driver->prepare_statement($class, $terms, $args);
    my $tbl = $class->datasource;
    my(%rec, @bind, @cols);
    my $cols = $class->column_names;

    my $primary_key = $class->properties->{primary_key};
    for my $col (@$cols) {
        if ($args->{fetchonly}) {
            next unless $args->{fetchonly}{$col};
        }
        my $dbcol  = $driver->db_column_name($tbl, $col);
        push @cols, $dbcol;
        push @bind, \$rec{$col};
    }
    my $tmp = "SELECT ";
    $tmp .= "DISTINCT " if $args->{join} && $args->{join}[3]{unique};
   
    $tmp .= join(', ', @cols) . "\n";
    my $sql = $tmp . mk_sql($stmt);
    my $dbh = $driver->r_handle($class->properties->{db});
    warn $sql if (SQLDEBUG);
    my $sth = $dbh->prepare_cached($sql);
    $sth->execute(@{ $stmt->{bind} });
    $sth->bind_columns(undef, @bind);

    # need to slurp 'offset' rows for DBs that cannot do it themselves
    if (!$driver->offset_implemented && $args->{offset}) {
        for (1..$args->{offset}) {
            $sth->fetch;
        }
    }

    my $iter = sub {
        unless ($sth->fetch) {
            $sth->finish;
            return;
        }
        my $obj;
        $obj = $class->new;
        $obj->set_values(\%rec);
        $obj->is_loaded(1);
        $obj;
    };
    
    if (wantarray) {
        my @objs;
        while (my $obj = $iter->()) {
            push @objs, $obj;
        }
        return @objs;
    } else {
        return $iter;
    }
}

sub lookup {
    my $driver = shift;
    my($class, $id) = @_;

    my $stmt = $driver->prepare_statement($class, $id);
    my $tbl = $class->datasource;
    my(%rec, @bind, @cols);
    my $cols = $class->column_names;
    for my $col (@$cols) {
        my $dbcol  = $driver->db_column_name($tbl, $col);
        push @cols, $col;
        push @bind, \$rec{$col};
    }
    my $tmp = "SELECT ";
    $tmp .= join(', ', @cols) . "\n";
    my $sql = $tmp . mk_sql($stmt);
    warn $sql if (SQLDEBUG);
    my $dbh = $driver->r_handle($class->properties->{db});
    my $sth = $dbh->prepare($sql) or return;
    $sth->execute(@{ $stmt->{bind} }) or return;
    $sth->bind_columns(undef, @bind);
    my @objs;
    while ($sth->fetch) {
        my $obj = $class->new;
        $obj->set_values(\%rec);
        $obj->is_loaded(1);
        unless (wantarray) {
            $sth->finish();
            return $obj;
        }
        push @objs, $obj;
    }
    $sth->finish;
    @objs;
}

sub select_one {
    my $driver = shift;
    my($dbh, $sql, $bind) = @_;
    my $sth = $dbh->prepare_cached($sql);
    $sth->execute(@$bind);
    $sth->bind_columns(undef, \my($val));
    $sth->fetch or return;
    $sth->finish;
    $val;
}

sub count {
    my $driver = shift;
    my($class, $terms, $args) = @_;
    my $stmt = $driver->prepare_statement($class, $terms, $args);
    ## Remove any order by clauses, because they will cause errors in
    ## some drivers (and they're not necessary)
    delete $stmt->{order};
    my $sql = "SELECT COUNT(*)\n" . mk_sql($stmt);
    warn $sql if (SQLDEBUG);
    my $count = $driver->select_one(
        $driver->r_handle($class->properties->{db}), $sql, $stmt->{bind}
    );
    $count;
}

sub data_exists {
    my $driver = shift;
    my($class, $terms, $args) = @_;

    # add a limit 1 to select only one row
    $args ||= {};
    $args->{limit} = 1;

    my $stmt = $driver->prepare_statement($class, $terms, $args);
    ## Remove any order by clauses, because they will cause errors in
    ## some drivers (and they're not necessary)
    delete $stmt->{order};
    my $sql = "SELECT 1\n" . mk_sql($stmt);
    warn $sql if (SQLDEBUG);
    my $exists = $driver->select_one(
        $driver->r_handle($class->properties->{db}), $sql, $stmt->{bind}
    );
    $exists;
}

sub min {
    my $driver = shift;
    my($class, $terms, $args) = @_;
    my $stmt = $driver->prepare_statement($class, $terms, $args);
    ## Remove any order by clauses, because they will cause errors in
    ## some drivers (and they're not necessary)
    delete $stmt->{order};
    my $field = $class->datasource . '_' . $args->{min_col};
    my $sql = "SELECT MIN($field)\n" . mk_sql($stmt);
    warn $sql if (SQLDEBUG);
    my $min = $driver->select_one(
        $driver->r_handle($class->properties->{db}), $sql, $stmt->{bind}
    );
    $min || undef;
}

sub sum {
    my $driver = shift;
    my($class, $terms, $args) = @_;
    my $stmt = $driver->prepare_statement($class, $terms, $args);
    ## Remove any order by clauses, because they will cause errors in
    ## some drivers (and they're not necessary)
    delete $stmt->{order};
    my $field = $class->datasource . '_' . $args->{sum_col};
    my $sql = "SELECT SUM($field)\n" . mk_sql($stmt);
    warn $sql if (SQLDEBUG);
    my $sum = $driver->select_one(
        $driver->r_handle($class->properties->{db}), $sql, $stmt->{bind}
    );
    $sum || 0;
}

sub exists {
    my $driver = shift;
    my($obj) = @_;
    return unless $obj->id;
    my $tbl = $obj->datasource;
    my $sql = "SELECT 1 FROM $tbl WHERE id = ?";
    my $dbh = $driver->r_handle($obj->properties->{db});
    warn $sql if (SQLDEBUG);
    my $sth = $dbh->prepare_cached($sql) or return;
    $sth->execute($obj->id) or return;
    my $exists = $sth->fetch;
    $sth->finish;
    $exists;
}

sub insert {
    my $driver = shift;
    my($obj) = @_;
    my $cols = $obj->column_names;
    unless ($obj->has_primary_key) {
        ## If we don't already have a primary key assigned for this object, we
        ## may need to generate one (depending on the underlying DB
        ## driver). If the driver gives us a new ID, we insert that into
        ## the new record; otherwise, we assume that the DB is using an
        ## auto-increment column of some sort, so we don't specify an ID
        ## at all.
        my $generated = $driver->generate_pk($obj);
        unless ($generated) {
            my $pk = $obj->properties->{primary_key};
            $pk = [ $pk ] unless ref($pk) eq 'ARRAY';
            my %pk = map { $_ => 1 } @$pk;
            $cols = [ grep !$pk{$_} || defined $obj->$_(), @$cols ];
        }
    }
    my $tbl = $obj->datasource;
    my $sql = "INSERT INTO $tbl\n";
    $sql .= '(' . join(', ', map $driver->db_column_name($tbl, $_), @$cols) . ')' . "\n" .
            'VALUES (' . join(', ', ('?') x @$cols) . ')' . "\n";
    my $dbh = $driver->rw_handle($obj->properties->{db});
    warn $sql if (SQLDEBUG);
    my $sth = $dbh->prepare_cached($sql);
    my $i = 1;
    my $col_defs = $obj->properties->{column_defs};
    for my $col (@$cols) {
        my $val = $obj->column($col);
        my $type = $col_defs->{$col} || 'char';
        my $attr = $driver->bind_param_attributes($type);
        $sth->bind_param($i++, $val, $attr);
    }
    $sth->execute;
    $sth->finish;

    ## Now, if we didn't have an object ID, we need to grab the
    ## newly-assigned ID.
    unless ($obj->has_primary_key) {
        $obj->id($driver->fetch_id($sth));
    }
    1;
}

sub update {
    my $driver = shift;
    my($obj) = @_;
    my $cols = $obj->column_names;
    my $pk = $obj->properties->{primary_key};
    $pk = [ $pk ] unless ref($pk) eq 'ARRAY';
    my %pk = map { $_ => 1 } @$pk;
    $cols = [ grep !$pk{$_}, @$cols ];
    my $tbl = $obj->datasource;
    my $sql = "UPDATE $tbl SET\n";
    $sql .= join(', ', map $driver->db_column_name($tbl, $_) . " = ?", @$cols) . "\n";
    my $stmt = $driver->prepare_statement(ref($obj), $obj->primary_key);
    $sql .= mk_sql_where($stmt);
    
    my $dbh = $driver->rw_handle($obj->properties->{db});
    warn $sql if (SQLDEBUG);
    my $sth = $dbh->prepare_cached($sql);
    my $i = 1;
    my $col_defs = $obj->properties->{column_defs};
    for my $col (@$cols) {
        my $val = $obj->column($col);
        my $type = $col_defs->{$col} || 'char';
        my $attr = $driver->bind_param_attributes($type);
        $sth->bind_param($i++, $val, $attr);
    }

    ## Bind the primary key value(s).
    for my $val (@{ $stmt->{bind} }) {
        $sth->bind_param($i++, $val);
    }

    $sth->execute;
    $sth->finish;
    1;
}

sub remove {
    my $driver = shift;
    my($obj) = @_;
    return unless $obj->has_primary_key;
    my $tbl = $obj->datasource;
    my $sql = "DELETE FROM $tbl\n";
    my $stmt = $driver->prepare_statement(ref($obj), $obj->primary_key);
    $sql .= mk_sql_where($stmt);
    my $dbh = $driver->rw_handle($obj->properties->{db});
    warn $sql if (SQLDEBUG);
    my $sth = $dbh->prepare_cached($sql);
    $sth->execute(@{ $stmt->{bind} });
    $sth->finish;
    1;
}

sub commit {
    my $driver = shift;
    if (my $dbh = $driver->dbh) {
        $dbh->commit;
    }
    1;
}

sub rollback {
    my $driver = shift;
    if (my $dbh = $driver->dbh) {
        $dbh->rollback;
    }
    1;
}

sub DESTROY {
    if (my $dbh = shift->dbh) {
        $dbh->disconnect if $dbh;
    }
}

our %Filters;
sub install_filters {
    my($class, $filters) = @_[1, 2];
    push @{ $Filters{$class} }, @$filters;
}
sub clear_filters {
    %Filters = ();
}

sub prepare_statement {
    my $driver = shift;
    my($class, $terms, $args) = @_;
    my $stmt = { bind => [] };

    my $tbl = $class->datasource;
    my $tbl_name = $tbl;

    if (my $join = $args->{join}) {
        my($j_class, $j_col, $j_terms, $j_args) = @$join;
        my $j_tbl = $j_class->datasource;
        my $j_tbl_name = $j_tbl;

        $stmt->{from} = [ $tbl_name, $j_tbl_name ];
        $driver->_update_statement($j_class, $j_terms, $j_args, $stmt);
        push @{ $stmt->{where} }, "${tbl}_id = ${j_tbl}_$j_col";

        ## We are doing a join, but some args and terms may have been
        ## specified for the "outer" piece of the join--for example, if
        ## we are doing a join of entry and comments where we end up with
        ## entries, sorted by the created_on date in the entry table, or
        ## filtered by author ID. In that case the sort or author ID will
        ## be specified in the spec for the Entry load, not for the join
        ## load.
        $driver->_update_statement($class, $terms, $args, $stmt);

        if ($j_args->{unique} && $j_args->{'sort'}) {
            ## If it's a distinct with sorting, we need to create
            ## a subselect to select the proper set of rows.
            my $cols = $class->column_names;
            $stmt->{from} = [
                '(SELECT ' .
                    join(', ', map "${tbl}_$_", @$cols) .
                    ", ${j_tbl}_$j_args->{'sort'}\n" .
                 mk_sql($stmt) .
                ') t '
            ];
            delete $stmt->{where};
            delete $stmt->{order};
        }

        ## If there's a LIMIT inside of the join arguments, promote it out
        ## to the outer level statement, to be handled below.
        if (my $n = $j_args->{limit}) {
            $args->{limit} = $n;
        }
    } else {
        $stmt->{from} = [ $tbl_name ];
        $driver->_update_statement($class, $terms, $args, $stmt);
    }
    $stmt->{limit} = $args->{limit};
    $stmt->{offset} = $args->{offset};
    unless ($stmt->{is_primary_key}) {
        my @filters = (@{ $args->{filters} || [] }, @{ $Filters{$class} || [] });
        for my $filter (@filters) {
            $filter->{object_class} = $class;
            $filter->modify_sql($stmt);
        }
    }
    $stmt;
}

sub mk_sql {
    my($stmt) = @_;
    my $sql = 'FROM ';
    if (my $join = $stmt->{join}) {
        ## If there's an actual JOIN statement, assume it's for joining with
        ## the main datasource for the object we're loading. So shift that
        ## off of the FROM list, and write the JOIN statement and condition.
        $sql .= shift(@{ $stmt->{from} }) . ' ' .
                uc($join->{type}) . ' JOIN ' . $join->{table} . ' ON ' .
                $join->{condition};
        $sql .= ', ' if @{ $stmt->{from} };
    }
    $sql .= join(', ', @{ $stmt->{from} }) . "\n";
    $sql .= mk_sql_where($stmt);
    if (my $order = $stmt->{order}) {
        $sql .= 'ORDER BY ' . $order->{column} . ' ' . $order->{desc} . "\n";
    }
    if (my $n = $stmt->{limit}) {
        $n =~ s/\D//g;   ## Get rid of any non-numerics.
        $sql .= sprintf "LIMIT %d%s\n", $n,
            ($stmt->{offset} ? " OFFSET $stmt->{offset}" : "");
    }
    $sql;
}

sub mk_sql_where {
    my($stmt) = @_;
    $stmt->{where} && @{ $stmt->{where} } ?
        'WHERE ' . join(' AND ', @{ $stmt->{where} }) . "\n" :
        '';
}

sub _update_statement {
    my $driver = shift;
    my($class, $terms, $args, $stmt) = @_;
    my $col_defs = $class->properties->{column_defs};
    my $tbl = $class->datasource;
    if (defined($terms)) {
        if (!ref($terms) || ref($terms) eq 'ARRAY') {
            ## $terms is the value for the primary key, so we wipe out
            ## any previous where and bind settings, if present.
            $stmt->{is_primary_key} = 1;
            $stmt->{where} = [];
            $stmt->{bind} = [];
            my $pk = $class->properties->{primary_key};
            $pk = [ $pk ] unless ref($pk) eq 'ARRAY';
            $terms = [ $terms ] unless ref($terms) eq 'ARRAY';
            my $i = 0;
            for my $col (@$pk) {
                push @{ $stmt->{where} }, $col . ' = ?';
                push @{ $stmt->{bind} }, $terms->[$i++];
            }
            return;
        }
        for my $col (keys %$terms) {
            die "Invalid/unsafe column name $col" if $col =~ /\W/;
            my $term = '';
            my $col_type = $col_defs->{$col} || 'char';
            if (ref($terms->{$col}) eq 'ARRAY') {
                if ( ($args->{range} && $args->{range}{$col}) ||
                     ($args->{range_incl} && $args->{range_incl}{$col}) ) {
                    my($start, $end) = @{ $terms->{$col} };
                    if ($start) {
                        $term = $args->{range_incl}
                          ? "$col >= ?"
                          : "$col > ?";
                        push @{ $stmt->{bind} }, $start;
                    }
                    $term .= " and " if $start && $end;
                    if ($end) {
                        $term .= $args->{range_incl}
                          ? "$col <= ?"
                          : "$col < ?";
                        push @{ $stmt->{bind} }, $end;
                    }
                } else {
                    # add multiple where clauses
                    # my $op = $args->{and_ops}{$col} ? 'AND' : 'OR';
                    my $op = 'OR'; 
                    $term = join " $op ", map { "$col = ?" } @{ $terms->{$col}};
                    foreach (@{ $terms->{$col} }) {
                        push @{ $stmt->{bind} }, $_;
                    }
                }
            } else {
                my $op;
                my $column = $col;

                $op = '=';
                $op = '<>'          if ($args->{not} && $args->{not}{$col});
                $op = 'LIKE'        if ($args->{like} && $args->{like}{$col});
                $op = 'IS NULL'     if ($args->{null} && $args->{null}{$col});
        $op = 'IS NOT NULL' if ($args->{not_null} && $args->{not_null}{$col});

                # if transform is supplied modify the column (UPPER, LOWER, etc.)
                if ($args->{transform} && $args->{transform}{$col}) {
                   $column = $args->{transform}{$col} . "($column)";
                }
                
        $term = "$column $op";

        # Unless this is a NULL/NOT NULL query, add a value placeholder
        unless (($args->{null} and $args->{null}->{$col}) or
            ($args->{not_null} and $args->{not_null}->{$col})) {
            $term .= ' ?';
            push @{ $stmt->{bind} }, $terms->{$col};
        }
            }
            push @{ $stmt->{where} }, "($term)";
        }
    }
    if (my $sv = $args->{start_val}) {
        my $col = $args->{sort} || $driver->primary_key;
        my $col_type = $col_defs->{$col} || 'char';
        my $cmp = $args->{direction} eq 'descend' ? '<' : '>';
        push @{ $stmt->{where} }, "($col $cmp ?)";
        push @{ $stmt->{bind} }, $sv;
    }
    if ($args->{'sort'} || $args->{direction}) {
        my $order = $args->{'sort'} || 'id';
        my $dir = $args->{direction} &&
                  $args->{direction} eq 'descend' ? 'DESC' : 'ASC';
        $stmt->{order} = {
            column => join('_', $tbl, $order),
            desc   => $dir,
        };
    }
}

1;