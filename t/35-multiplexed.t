# $Id$

use strict;

use lib 't/lib/multiplexed';

require 't/lib/db-common.pl';

use Test::Exception;
use Test::More;
unless (eval { require DBD::SQLite }) {
    plan skip_all => 'Tests require DBD::SQLite';
}
plan tests => 16;

setup_dbs({
    global1   => [ qw( ingredient2recipe ) ],
    global2   => [ qw( ingredient2recipe ) ],
});

use Ingredient2Recipe;

my $obj;

for my $driver (@{ Ingredient2Recipe->driver->drivers }) {
    isa_ok $driver, 'Data::ObjectDriver::Driver::DBI';
}

dies_ok { Ingredient2Recipe->lookup } 'lookup dies';
dies_ok { Ingredient2Recipe->lookup_multi } 'lookup_multi dies';
dies_ok { Ingredient2Recipe->exists } 'exists dies';

$obj = Ingredient2Recipe->new;
$obj->ingredient_id(1);
$obj->recipe_id(5);
$obj->insert;

for my $driver (@{ Ingredient2Recipe->driver->drivers }) {
    my $ok = $driver->select_one(<<SQL, [ 1, 5 ]);
SELECT 1 FROM ingredient2recipe WHERE ingredient_id = ? and recipe_id = ?
SQL
    is $ok, 1, "Record exists in $driver backend database";
}

_check_object($obj);

is(Ingredient2Recipe->remove({ ingredient_id => 1, recipe_id => 5 }, { nofetch => 1 }), 2, 'Removed 2 records');

for my $driver (@{ Ingredient2Recipe->driver->drivers }) {
    my $ok = !$driver->select_one(<<SQL, [ 1, 5 ]);
SELECT 1 FROM ingredient2recipe WHERE ingredient_id = ? and recipe_id = ?
SQL
    is $ok, 1, "Record is removed from $driver backend database";
}

sub _check_object {
    my($obj) = @_;

    my($obj2) = Ingredient2Recipe->search({ ingredient_id => $obj->ingredient_id });
    isa_ok $obj2, 'Ingredient2Recipe';
    is $obj2->ingredient_id, $obj->ingredient_id;
    is $obj2->recipe_id, $obj->recipe_id;

    ($obj2) = Ingredient2Recipe->search({ recipe_id => $obj->recipe_id });
    isa_ok $obj2, 'Ingredient2Recipe';
    is $obj2->ingredient_id, $obj->ingredient_id;
    is $obj2->recipe_id, $obj->recipe_id;
}

teardown_dbs(qw( global1 global2 ));
