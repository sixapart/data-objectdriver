# $Id$

use strict;

use lib 't/lib';

use Test::More;
use Test::Exception;
use DodTestUtil;
BEGIN { DodTestUtil->check_driver }

plan tests => 3;

use ErrorTest;

setup_dbs({
    global => [ qw( error_test ) ],
});

my $t = ErrorTest->new;
$t->foo('bar');
lives_ok { $t->insert } 'Inserted first record';

$t = ErrorTest->new;
$t->foo('bar');
dies_ok { $t->insert } 'Second insert fails';

is(ErrorTest->driver->last_error,
   Data::ObjectDriver::Errors->UNIQUE_CONSTRAINT,
   'Failed because of a unique constraint');

END { teardown_dbs(qw( global )); }
