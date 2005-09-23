# $Id$

use strict;
use File::Spec;

sub db_filename {
    my($dbname) = @_;
    $dbname . '.db';
}

sub setup_dbs {
    my($info) = @_;
    teardown_dbs(keys %$info);
    for my $dbname (keys %$info) {
        my $dbh = DBI->connect('dbi:SQLite:dbname=' . db_filename($dbname),
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
