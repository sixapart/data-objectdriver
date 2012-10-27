package OracleDriver;

use Data::ObjectDriver::Driver::DBI;

my $dsn = $ENV{ORACLE_DSN} || '';
my ( $username, $password ) = split '/', ( $ENV{ORACLE_USERID} || '' );

sub driver {
    return undef if !( $dsn && $username && $password );

    Data::ObjectDriver::Driver::DBI->new(
        dsn      => $dsn,
        username => $username,
        password => $password,
    );
}

package Wine;

use base qw( Data::ObjectDriver::BaseObject );
__PACKAGE__->install_properties(
    {   columns     => [ 'id', 'cluster_id', 'name', 'content', 'binchar' ],
        datasource  => 'wines',
        primary_key => 'id',
        column_defs => { content => 'blob', binchar => 'binchar' },
        driver      => OracleDriver::driver,
    }
);

package main;

use Test::More;

unless ( eval { require DBD::Oracle } ) {
    plan skip_all => 'Tests require DBD::Oracle';
}

unless (OracleDriver::driver) {
    plan skip_all => 'Tests require DSN and USERID for connecting Oracle DB';
}

my $dbh = OracleDriver::driver->init_db;

sub setup {
    eval { $dbh->do('DROP TABLE wines'); };
    $dbh->do( <<__SQL__);
CREATE TABLE wines (
    id INTEGER NOT NULL PRIMARY KEY,
    cluster_id SMALLINT,
    name VARCHAR(50),
    content BLOB,
    binchar CHAR(50),
    rating SMALLINT
)
__SQL__

    my $wine = Wine->new;
    $wine->id(1);
    $wine->name("Saumur Champigny, Le Grand Clos 2001");
    $wine->save;
}
setup();

sub fetch_cursor_count {
    $dbh->selectcol_arrayref('SELECT COUNT(*) FROM V$OPEN_CURSOR')->[0];
}

subtest 'Cursor leak' => sub {
    my $repeat_count = 100;
    my $start_cursor_count = eval { fetch_cursor_count() };
    if ($@) {
        plan skip_all => 'Does not have previrege to fetch cursor count';
    }

    for ( my $i = 1; $i <= $repeat_count; $i++ ) {
        Wine->search( { id => [ (1) x $i ] } );
    }

    my $end_cursor_count = fetch_cursor_count();

    ok( $end_cursor_count - $start_cursor_count < $repeat_count,
        'Cursor count should not be increased' );

    done_testing();
};

done_testing();
