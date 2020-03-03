package DodTestUtil;

use strict;
use Exporter qw/import/;
use File::Spec;
use Test::More;

our @EXPORT = qw/setup_dbs teardown_dbs/;

my %Requires = (
    SQLite     => 'DBD::SQLite',
    MySQL      => 'Test::mysqld',
    PostgreSQL => 'Test::PostgreSQL',
    Oracle     => 'DBD::Oracle',
    SQLServer  => 'DBD::ODBC',
);

my %TestDB;

sub driver { $ENV{DOD_TEST_DRIVER} || 'SQLite' }

sub check_driver {
    my $driver = driver();
    my $module = $Requires{$driver} or plan skip_all => "Uknonwn driver: $driver";
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

sub dsn {
    my($dbname) = @_;
    my $driver = driver();
    if ( my $dsn = env('DOD_TEST_DSN', $dbname) ) {
        return "$dsn;dbname=$dbname";
    }
    if ( $driver eq 'MySQL' ) {
        $TestDB{$dbname} ||= Test::mysqld->new(
            my_cnf => {
                'skip-networking' => '', # no TCP socket
                'sql-mode' => 'TRADITIONAL,NO_AUTO_VALUE_ON_ZERO,ONLY_FULL_GROUP_BY',
            }
        ) or die $Test::mysqld::errstr;
        return $TestDB{$dbname}->dsn;
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
        return 'dbi:SQLite:' . db_filename($dbname);
    }
}

sub setup_dbs {
    my($info) = @_;
    teardown_dbs(keys %$info);
    for my $dbname (keys %$info) {
        my $dbh = DBI->connect(
            dsn($dbname),
            env('DOD_TEST_USER', $dbname),
            env('DOD_TEST_PASS', $dbname),
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
    for my $db (@dbs) {
        next unless $driver eq 'SQLite';
        my $file = db_filename($db);
        next unless -e $file;
        unlink $file or die "Can't teardown $db: $!";
    }
}

sub create_sql {
    my($table) = @_;
    my $driver = driver();
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
