package User;
use strict;
use warnings;
use base qw( Data::ObjectDriver::BaseObject );
use DodTestUtil;

use Data::ObjectDriver::Driver::DBI;

our $LAST_ID = 0;
__PACKAGE__->install_properties({
    columns => [ qw/
        user_id
        first_name
        last_name
        address1
        address2
        email
        hair_color
        eyes_color
        timezone
        language1
        language2
        language3
        language4
        language5
        language6
        SSN
        TIN
        PIN
        city
    /],
    datasource => 'user',
    primary_key => 'user_id',
    driver => Data::ObjectDriver::Driver::DBI->new(
        dsn      => DodTestUtil::dsn('global'),
        reuse_dbh => 1,
    ),
    genereate_pk => sub { ++$LAST_ID },
});

1;
