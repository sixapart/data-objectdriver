# $Id$

package Blog;
use strict;
use warnings;
use base 'Data::ObjectDriver::BaseObject';
use Data::ObjectDriver::Driver::DBI;
use DodTestUtil;

my $username = DodTestUtil::env('DOD_TEST_USER', 'blog');
my $password = DodTestUtil::env('DOD_TEST_PASS', 'blog');

__PACKAGE__->install_properties({
    columns => ['ID', 'PARENT_ID', 'NAME'],
    datasource  => 'BLOG',
    primary_key => 'ID',
    driver      => Data::ObjectDriver::Driver::DBI->new(
        dsn => DodTestUtil::dsn('global'),
        $username ? (username => $username) : (),
        $password ? (password => $password) : (),
    ),
});

1;
