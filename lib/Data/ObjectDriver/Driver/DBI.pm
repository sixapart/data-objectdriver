# $Id$

package Data::ObjectDriver::Driver::DBI;
use strict;
use base qw( Data::ObjectDriver Class::Accessor::Fast );

use DBI;
use Carp ();
use Data::ObjectDriver::SQL;

__PACKAGE__->mk_accessors(qw( dsn username password dbh ));

# set to 1 during development to get sql statements in the error log
use constant SQLDEBUG => 0;

sub init {
    my $driver = shift;
    my %param = @_;
    for my $key (keys %param) {
        $driver->$key($param{$key});
    }
    ## Rebless the driver into the DSN-specific subclass (e.g. "mysql").
    my($type) = $driver->dsn =~ /^dbi:(\w*)/;
    my $class = ref($driver) . '::' . $type;
    eval "use $class";
    die $@ if $@;
    bless $driver, $class;
    $driver;
}

sub generate_pk {
    my $driver = shift;
    if (my $generator = $driver->pk_generator) {
        return $generator->(@_);
    }
}
sub fetch_id { undef }
sub offset_implemented { 1 }

sub db_column_name {
    my ($driver, $table, $column) = @_; 
    return join '.', $table, $column;
}

# Override in DB Driver to pass correct attributes to bind_param call
sub bind_param_attributes { return undef }

sub init_db {
    my $driver = shift;
    my $dbh;
    eval {
        local $SIG{ALRM} = sub { die "alarm\n" };
        $dbh = DBI->connect($driver->dsn, $driver->username, $driver->password,
            { RaiseError => 1, PrintError => 0, AutoCommit => 1 })
            or Carp::croak("Connection error: " . $DBI::errstr);
        alarm 0;
    };
    if ($@) {
        Carp::croak(@$ eq "alarm\n" ? "Connection timeout" : $@);
    }
    $dbh;
}

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
    my $sql = $tmp . $stmt->as_sql;
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

sub primary_key_to_terms {
    my $driver = shift;
    my($class, $id) = @_;
    my $pk = $class->properties->{primary_key};
    $pk = [ $pk ] unless ref($pk) eq 'ARRAY';
    $id = [ $id ] unless ref($id) eq 'ARRAY';
    my $i = 0;
    my %terms;
    @terms{@$pk} = @$id;
    \%terms;
}

sub lookup {
    my $driver = shift;
    my($class, $id) = @_;
    my @obj = $driver->search($class,
        $driver->primary_key_to_terms($class, $id), { limit => 1 });
    $obj[0];
}

## xxx refactor to use an OR search
sub lookup_multi {
    my $driver = shift;
    my($class, $ids) = @_;
    my %got;
    for my $id (@$ids) {
        $got{$id} = $driver->lookup($class, $id);
    }
    \%got;
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
    my $sql = "SELECT COUNT(*)\n" . $stmt->as_sql;
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
    my $sql = "SELECT 1\n" . $stmt->as_sql;
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
    my $sql = "SELECT MIN($field)\n" . $stmt->as_sql;
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
    my $sql = "SELECT SUM($field)\n" . $stmt->as_sql;
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
        $obj->id($driver->fetch_id(ref($obj), $dbh, $sth));
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
    my $stmt = $driver->prepare_statement(ref($obj),
        $driver->primary_key_to_terms(ref($obj), $obj->primary_key));
    $sql .= $stmt->as_sql_where;
    
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
    my $stmt = $driver->prepare_statement(ref($obj),
        $driver->primary_key_to_terms(ref($obj), $obj->primary_key));
    $sql .= $stmt->as_sql_where;
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

sub prepare_statement {
    my $driver = shift;
    my($class, $terms, $args) = @_;
    my $stmt = Data::ObjectDriver::SQL->new;
    my $tbl = $class->datasource;
    $stmt->from([ $tbl ]);
    if (defined($terms)) {
        for my $col (keys %$terms) {
            $stmt->add_where(join('.', $tbl, $col), $terms->{$col});
        }
    }
    $stmt->limit($args->{limit});
    $stmt->offset($args->{offset});
    if ($args->{sort} || $args->{direction}) {
        my $order = $args->{sort} || 'id';
        my $dir = $args->{direction} &&
                  $args->{direction} eq 'descend' ? 'DESC' : 'ASC';
        $stmt->order({
            column => $order,
            desc   => $dir,
        });
    }
    $stmt;
}

1;
