# $Id$

package Entry;
use strict;
use warnings;
use base 'Data::ObjectDriver::BaseObject';
use Data::ObjectDriver::Driver::DBI;
use DodTestUtil;

my $username = DodTestUtil::env('DOD_TEST_USER', 'entry');
my $password = DodTestUtil::env('DOD_TEST_PASS', 'entry');

__PACKAGE__->install_properties({
    columns => ['ID', 'BLOG_ID', 'TITLE', 'TEXT'],
    datasource  => 'ENTRY',
    primary_key => 'ID',
    driver      => Data::ObjectDriver::Driver::DBI->new(
        dsn => DodTestUtil::dsn('global'),
        $username ? (username => $username) : (),
        $password ? (password => $password) : (),
    ),
});

1;
