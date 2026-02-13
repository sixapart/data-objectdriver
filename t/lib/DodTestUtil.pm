package DodTestUtil;

use strict;
use warnings;
use Exporter qw/import/;
use File::Spec;
use Test::More;

our @EXPORT = qw/setup_dbs teardown_dbs disconnect_all/;

my %Requires = (
    SQLite     => 'DBD::SQLite',
    MySQL      => 'Test::mysqld',
    MariaDB    => 'Test::mysqld',
    PostgreSQL => 'Test::PostgreSQL',
    Oracle     => 'DBD::Oracle',
    SQLServer  => 'DBD::ODBC',
);

my %TestDB;
my $Driver;

sub driver { $Driver ||= _driver() }

sub _driver {
    my $driver = $ENV{DOD_TEST_DRIVER} || 'SQLite';
    return $driver if exists $Requires{$driver};
    return 'PostgreSQL' if lc $driver eq 'pg';
    for my $key (keys %Requires) {
        return $key if lc $key eq lc $driver;
    }
    plan skip_all => "Unknown driver: $driver";
}

sub check_driver {
    my $driver = driver();
    my $module = $Requires{$driver};
    unless ( eval "require $module; 1" ) {
        plan skip_all => "Test requires $module";
    }
    if ( $driver ne 'SQLite' and !eval { require SQL::Translator; 1 } ) {
        plan skip_all => "Test requires SQL::Translator";
    }
}

sub env {
    my ($key, $dbname) = @_;
    $ENV{$key} || $ENV{$key . "_" . uc $dbname} || '';
}

sub db_filename {
    my($dbname) = @_;
    $dbname . $$ . '.db';
}

my $test_mysqld_dsn;
sub dsn {
    my($dbname) = @_;
    my $driver = driver();
    if ( my $dsn = env('DOD_TEST_DSN', $dbname) ) {
        return "$dsn;dbname=$dbname";
    }
    if ( $driver =~ /MySQL|MariaDB/ ) {
        if ( $driver eq 'MariaDB' && !$test_mysqld_dsn ) {
            my $help = `mysql --help`;
            my ($mariadb_major_version, $mariadb_minor_version) = $help =~ /\A.*?([0-9]+)\.([0-9]+)\.[0-9]+\-MariaDB/;
            no warnings 'redefine';
            $test_mysqld_dsn = \&Test::mysqld::dsn;
            *Test::mysqld::dsn = sub {
                my $dsn = $test_mysqld_dsn->(@_);
                # cf. https://github.com/kazuho/p5-test-mysqld/issues/32
                $dsn =~ s/;user=root// if $mariadb_major_version && $mariadb_major_version >= 10 && $mariadb_minor_version > 3;
                $dsn;
            };
        }
        {
            no warnings 'redefine';
            *Test::mysqld::wait_for_stop = sub {
                my $self = shift;
                local $?;    # waitpid may change this value :/
                my $ct = 0;
                # XXX: modified
                while (waitpid($self->pid, POSIX::WNOHANG()) <= 0) {
                    sleep 1;
                    if ($ct++ > 10) {
                        kill 9, $self->pid;
                    }
                }
                $self->pid(undef);
                # might remain for example when sending SIGKILL
                unlink $self->my_cnf->{'pid-file'};
            };
        }
        $TestDB{$dbname} ||= Test::mysqld->new(
            my_cnf => {
                'skip-networking' => '', # no TCP socket
                'skip-name-resolve' => '',
                'default_authentication_plugin' => 'mysql_native_password',
                'sql-mode' => 'TRADITIONAL,NO_AUTO_VALUE_ON_ZERO,ONLY_FULL_GROUP_BY',
                'bind-address' => '127.0.0.1',
                'disable-log-bin' => '',
                'performance_schema' => 'OFF',
            }
        ) or die $Test::mysqld::errstr;
        my $dsn = $TestDB{$dbname}->dsn;
        if ( $driver eq 'MariaDB' ) {
            $dsn =~ s/^dbi:mysql/dbi:MariaDB/i;
            $dsn =~ s/mysql_/mariadb_/ig;
        }
        return $dsn;
    }
    if ( $driver eq 'PostgreSQL' ) {
        $TestDB{$dbname} ||= Test::PostgreSQL->new(
            extra_initdb_args => '--locale=C --encoding=UTF-8',
            pg_config => <<'CONF',
lc_messages = 'C'
CONF
        ) or die $Test::PostgreSQL::errstr;
        return $TestDB{$dbname}->dsn;
    }
    if ( $driver eq 'SQLite' ) {
        $TestDB{$dbname} ||= db_filename($dbname);
        return 'dbi:SQLite:' . $TestDB{$dbname};
    }
}

sub setup_dbs {
    my($info) = @_;
    teardown_dbs(keys %$info);
    for my $dbname (keys %$info) {
        my $dbh = DBI->connect(
            dsn($dbname),
            env('DOD_TEST_USER', $dbname) || undef,
            env('DOD_TEST_PASS', $dbname) || undef,
            { RaiseError => 1, PrintError => 0, ShowErrorStatement => 1 });
        for my $table (@{ $info->{$dbname} }) {
            $dbh->do($_) for create_sql($table);
        }
        $dbh->disconnect;
    }
}

sub teardown_dbs {
    my(@dbs) = @_;
    my $driver = driver();
    return unless $driver eq 'SQLite';
    for my $db (@dbs) {
        my $file = $TestDB{$db};
        next unless -e $file;
        unlink $file or die "Can't teardown $file: $!";
    }
}

sub disconnect_all {
    my @tables = @_;
    return unless driver() eq 'SQLite';
    for my $table (@tables) {
        my $driver = $table->driver;
        if ($driver->can('fallback')) {
            $driver = $driver->fallback;
        }
        if ($driver->can('dbh')) {
            my $dbh = $driver->dbh or next;
            $dbh->disconnect;
        }
        elsif ($driver->can('drivers')) {
            for my $d (@{ $driver->drivers }) {
                my $dbh = $d->dbh or next;
                $dbh->disconnect;
            }
        }
        else {
            my @drivers = @{ $driver->get_driver->(undef, {multi_partition => 1})->partitions };
            for my $d (@drivers) {
                my $dbh = $d->dbh or next;
                $dbh->disconnect;
            }
        }
    }
}

sub create_sql {
    my($table) = @_;
    my $driver = driver();
    $driver = 'MySQL' if $driver eq 'MariaDB';
    my $file = File::Spec->catfile('t', 'schemas', $table . '.sql');
    open my $fh, $file or die "Can't open $file: $!";
    my $sql = do { local $/; <$fh> };
    close $fh;
    if ( $driver ne 'SQLite' ) {
        $sql .= ';';
        my $drop_table = (grep /^DOD_TEST_DSN/, keys %ENV) ? 1 : 0;
        my $sqlt = SQL::Translator->new(
            parser         => 'SQLite',
            producer       => $driver,
            no_comments    => 1,
            add_drop_table => $drop_table,
        );
        $sql = $sqlt->translate(\$sql) or die $sqlt->error;
        return split /;\s*/s, $sql;
    }
    $sql;
}

1;
