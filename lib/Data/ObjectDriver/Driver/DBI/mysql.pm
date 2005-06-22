# $Id$

package Data::ObjectDriver::Driver::DBI::mysql;
use strict;
use base qw( Data::ObjectDriver::Driver::DBI );

use Carp qw( croak );

sub fetch_id { $_[1]->{mysql_insertid} || $_[1]->{insertid} }

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

sub commit   { 1 }
sub rollback { 1 }

1;
