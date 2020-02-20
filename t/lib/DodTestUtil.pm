package DodTestUtil;

use strict;
use Exporter qw/import/;
use File::Spec;

our @EXPORT = qw/setup_dbs teardown_dbs/;

sub db_filename {
    my($dbname) = @_;
    $dbname . $$ . '.db';
}

sub dsn {
    my($dbname) = @_;
    return 'dbi:SQLite:' . db_filename($dbname);
}

sub setup_dbs {
    my($info) = @_;
    teardown_dbs(keys %$info);
    for my $dbname (keys %$info) {
        my $dbh = DBI->connect(dsn($dbname),
            '', '', { RaiseError => 1, PrintError => 0 });
        for my $table (@{ $info->{$dbname} }) {
            $dbh->do( create_sql($table) );
        }
        $dbh->disconnect;
    }
}

sub teardown_dbs {
    my(@dbs) = @_;
    for my $db (@dbs) {
        my $file = db_filename($db);
        next unless -e $file;
        unlink $file or die "Can't teardown $db: $!";
    }
}

sub create_sql {
    my($table) = @_;
    my $file = File::Spec->catfile('t', 'schemas', $table . '.sql');
    open my $fh, $file or die "Can't open $file: $!";
    my $sql = do { local $/; <$fh> };
    close $fh;
    $sql;
}

1;
