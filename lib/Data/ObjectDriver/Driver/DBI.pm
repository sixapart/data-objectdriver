# $Id$

package Data::ObjectDriver::Driver::DBI;
use strict;
use base qw( Data::ObjectDriver Class::Accessor::Fast );

use DBI;
use Carp ();
use Data::ObjectDriver::SQL;
use Data::ObjectDriver::Driver::DBD;

__PACKAGE__->mk_accessors(qw( dsn username password dbh get_dbh dbd ));

sub init {
    my $driver = shift;
    my %param = @_;
    for my $key (keys %param) {
        $driver->$key($param{$key});
    }
    ## Create a DSN-specific driver (e.g. "mysql").
    my $type;
    if (my $dsn = $driver->dsn) {
        ($type) = $dsn =~ /^dbi:(\w*)/;
    } elsif (my $dbh = $driver->dbh) {
        $type = $dbh->{Driver}{Name};
    } elsif (my $getter = $driver->get_dbh) {
## Ugly. Shouldn't have to connect just to get the driver name.
        my $dbh = $getter->();
        $type = $dbh->{Driver}{Name};
    }
    $driver->dbd(Data::ObjectDriver::Driver::DBD->new($type));
    $driver;
}

sub generate_pk {
    my $driver = shift;
    if (my $generator = $driver->pk_generator) {
        return $generator->(@_);
    }
}

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
    $driver->dbd->init_dbh($dbh);
    $dbh;
}

sub rw_handle {
    my $driver = shift;
    my $db = shift || 'main';
    my $dbh = $driver->dbh;
    unless ($dbh) {
        if (my $getter = $driver->get_dbh) {
            $dbh = $getter->();
        } else {
            $dbh = $driver->init_db($db) or die $driver->errstr;
            $driver->dbh($dbh);
        }
    }
    $dbh;
}
*r_handle = \&rw_handle;

sub fetch_data {
    my $driver = shift;
    my($obj) = @_;
    return unless $obj->has_primary_key;
    my $terms = $driver->primary_key_to_terms(ref($obj), $obj->primary_key);
    my $args  = { limit => 1 };
    my $rec = {};
    my $sth = $driver->fetch($rec, $obj, $terms, $args);
    $sth->fetch;
    $sth->finish;
    return $rec;
}

sub fetch {
    my $driver = shift;
    my($rec, $class, $orig_terms, $orig_args) = @_;
    
    ## Use (shallow) duplicates so the pre_search trigger can modify them.
    my $terms = defined $orig_terms ? { %$orig_terms } : undef;
    my $args  = defined $orig_args  ? { %$orig_args  } : undef;
    $class->call_trigger('pre_search', $terms, $args);


    my $stmt = $driver->prepare_statement($class, $terms, $args);
    my $tbl = $class->datasource;
    my(@bind, @cols);
    my $cols = $class->column_names;

    my $primary_key = $class->properties->{primary_key};
    my $dbd = $driver->dbd;
    my %fetch = $args->{fetchonly} ?
        (map { $_ => 1 } @{ $args->{fetchonly} }) : ();
    for my $col (@$cols) {
        if (keys %fetch) {
            next unless $fetch{$col};
        }
        my $dbcol = join '.', $tbl, $dbd->db_column_name($tbl, $col);
        push @cols, $dbcol;
        push @bind, \$rec->{$col};
    }
    my $tmp = "SELECT ";
    $tmp .= join(', ', @cols) . "\n";
    my $sql = $tmp . $stmt->as_sql;
    my $dbh = $driver->r_handle($class->properties->{db});
    $driver->debug($sql, $stmt->{bind});
    my $sth = $dbh->prepare_cached($sql);
    $sth->execute(@{ $stmt->{bind} });
    $sth->bind_columns(undef, @bind);

    # need to slurp 'offset' rows for DBs that cannot do it themselves
    if (!$driver->dbd->offset_implemented && $args->{offset}) {
        for (1..$args->{offset}) {
            $sth->fetch;
        }
    }

    # xxx what happens if $sth goes out of scope without finish() being called ?
    $sth;
}

sub search {
    my($driver) = shift;
    my($class, $terms, $args) = @_;

    my $rec = {};
    my $sth = $driver->fetch($rec, $class, $terms, $args);

    my $iter = sub {
        ## This is kind of a hack--we need $driver to stay in scope,
        ## so that the DESTROY method isn't called. So we include it
        ## in the scope of the closure.
        my $d = $driver;

        unless ($sth->fetch) {
            $sth->finish;
            return;
        }
        my $obj;
        $obj = $class->new;
        $obj->set_values($rec);
        ## Don't need a duplicate as there's no previous version in memory
        ## to preserve.
        $obj->call_trigger('post_load');
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
    my $pk = $class->primary_key_tuple;
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
    my @got;
    for my $id (@$ids) {
        push @got, $driver->lookup($class, $id);
    }
    \@got;
}

sub select_one {
    my $driver = shift;
    my($sql, $bind) = @_;
    my $dbh = $driver->r_handle;
    my $sth = $dbh->prepare_cached($sql);
    $sth->execute(@$bind);
    $sth->bind_columns(undef, \my($val));
    $sth->fetch or return;
    $sth->finish;
    $val;
}

sub exists {
    my $driver = shift;
    my($obj) = @_;
    return unless $obj->has_primary_key;
    my $tbl = $obj->datasource;
    my $stmt = $driver->prepare_statement(ref($obj),
        $driver->primary_key_to_terms(ref($obj), $obj->primary_key),
        { limit => 1 });
    my $sql = "SELECT 1 FROM $tbl\n";
    $sql .= $stmt->as_sql_where;
    my $dbh = $driver->r_handle($obj->properties->{db});
    $driver->debug($sql, $stmt->{bind});
    my $sth = $dbh->prepare_cached($sql);
    $sth->execute(@{ $stmt->{bind} });
    my $exists = $sth->fetch;
    $sth->finish;
    $exists;
}

sub insert {
    my $driver = shift;
    my($orig_obj) = @_;

    ## Use a duplicate so the pre_save trigger can modify it.
    my $obj = $orig_obj->clone;
    $obj->call_trigger('pre_save');
    
    my $cols = $obj->column_names;
    unless ($obj->has_primary_key) {
        ## If we don't already have a primary key assigned for this object, we
        ## may need to generate one (depending on the underlying DB
        ## driver). If the driver gives us a new ID, we insert that into
        ## the new record; otherwise, we assume that the DB is using an
        ## auto-increment column of some sort, so we don't specify an ID
        ## at all.
        my $pk = $obj->primary_key_tuple;
        if(my $generated = $driver->generate_pk($obj)) {
            ## The ID is the only thing we *are* allowed to change on
            ## the original object.
            $orig_obj->$_($obj->$_) for @$pk;
        } else {
            my %pk = map { $_ => 1 } @$pk;
            $cols = [ grep !$pk{$_} || defined $obj->$_(), @$cols ];
        }
    }
    my $tbl = $obj->datasource;
    my $sql = "INSERT INTO $tbl\n";
    my $dbd = $driver->dbd;
    $sql .= '(' . join(', ',
                  map $dbd->db_column_name($tbl, $_),
                  @$cols) .
            ')' . "\n" .
            'VALUES (' . join(', ', ('?') x @$cols) . ')' . "\n";
    my $dbh = $driver->rw_handle($obj->properties->{db});
    $driver->debug($sql, $obj->{column_values});
    my $sth = $dbh->prepare_cached($sql);
    my $i = 1;
    my $col_defs = $obj->properties->{column_defs};
    for my $col (@$cols) {
        my $val = $obj->column($col);
        my $type = $col_defs->{$col} || 'char';
        my $attr = $dbd->bind_param_attributes($type);
        $sth->bind_param($i++, $val, $attr);
    }
    $sth->execute;
    $sth->finish;

    ## Now, if we didn't have an object ID, we need to grab the
    ## newly-assigned ID.
    unless ($obj->has_primary_key) {
        my $pk = $obj->primary_key_tuple;
        my $id_col = $pk->[0]; # XXX are we sure we will always use '0' ?
        my $id = $dbd->fetch_id(ref($obj), $dbh, $sth);
        $obj->$id_col($id);
        ## The ID is the only thing we *are* allowed to change on
        ## the original object.
        $orig_obj->$id_col($id);
    }
    1;
}

sub update {
    my $driver = shift;
    my($orig_obj) = @_;

    ## Use a duplicate so the pre_save trigger can modify it.
    my $obj = $orig_obj->clone;
    $obj->call_trigger('pre_save');

    my $cols = $obj->column_names;
    my $pk = $obj->primary_key_tuple;
    my %pk = map { $_ => 1 } @$pk;
    $cols = [ grep !$pk{$_}, @$cols ];

    ## If there's no non-PK column, update() is no-op
    @$cols or return 1;

    my $tbl = $obj->datasource;
    my $sql = "UPDATE $tbl SET\n";
    my $dbd = $driver->dbd;
    $sql .= join(', ',
            map $dbd->db_column_name($tbl, $_) . " = ?",
            @$cols) . "\n";
    my $stmt = $driver->prepare_statement(ref($obj),
        $driver->primary_key_to_terms(ref($obj), $obj->primary_key));
    $sql .= $stmt->as_sql_where;
    
    my $dbh = $driver->rw_handle($obj->properties->{db});
    $driver->debug($sql, $obj->{column_values});
    my $sth = $dbh->prepare_cached($sql);
    my $i = 1;
    my $col_defs = $obj->properties->{column_defs};
    for my $col (@$cols) {
        my $val = $obj->column($col);
        my $type = $col_defs->{$col} || 'char';
        my $attr = $dbd->bind_param_attributes($type);
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
    $driver->debug($sql, $stmt->{bind});
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
