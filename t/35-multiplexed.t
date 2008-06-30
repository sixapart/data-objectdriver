# $Id$

use strict;

use lib 't/lib/multiplexed';

require 't/lib/db-common.pl';

use Test::Exception;
use Test::More;
unless (eval { require DBD::SQLite }) {
    plan skip_all => 'Tests require DBD::SQLite';
}
plan tests => 42;

setup_dbs({
    global1   => [ qw( ingredient2recipe ) ],
    global2   => [ qw( ingredient2recipe ) ],
});

use Ingredient2Recipe;

my $obj;
my $objs;

for my $driver (@{ Ingredient2Recipe->driver->drivers }) {
    isa_ok $driver, 'Data::ObjectDriver::Driver::DBI';
}

$obj = Ingredient2Recipe->new;
$obj->ingredient_id(1);
$obj->recipe_id(5);
$obj->insert;

lives_ok { $obj = Ingredient2Recipe->lookup(5) } 'lookup lives';
lives_ok { $objs = Ingredient2Recipe->lookup_multi([5, 5]) } 'lookup_multi lives';
lives_ok { $obj->exists } 'exists lives';

is $obj->ingredient_id, 1;
is $obj->recipe_id, 5;
isa_ok( $_, 'Ingredient2Recipe' ) for @$objs;
is $objs->[0]->ingredient_id, 1;
is $objs->[1]->ingredient_id, 1;

for my $driver (@{ Ingredient2Recipe->driver->drivers }) {
    my $ok = $driver->select_one(<<SQL, [ 1, 5 ]);
SELECT 1 FROM ingredient2recipe WHERE ingredient_id = ? and recipe_id = ?
SQL
    is $ok, 1, "Record exists in $driver backend database";
}

_check_object($obj);

is(Ingredient2Recipe->remove({ ingredient_id => 1, recipe_id => 5 }, { nofetch => 1 }), 2, 'Removed 2 records for 1 object');

for my $driver (@{ Ingredient2Recipe->driver->drivers }) {
    my $ok = !$driver->select_one(<<SQL, [ 1, 5 ]);
SELECT 1 FROM ingredient2recipe WHERE ingredient_id = ? and recipe_id = ?
SQL
    is $ok, 1, "Record is removed from $driver backend database";
}

## check transactions
$obj = Ingredient2Recipe->new;
$obj->ingredient_id(10);
$obj->recipe_id(50);
$obj->insert;

Data::ObjectDriver::BaseObject->begin_work();
$obj->value1("will be rolled back");
$obj->update;
Data::ObjectDriver::BaseObject->rollback();
$obj->refresh;
is $obj->value1, undef, "properly rolled back";
_check_object($obj);

Data::ObjectDriver::BaseObject->begin_work();
$obj->value1("commit");
$obj->update;
Data::ObjectDriver::BaseObject->commit();
$obj->refresh;
is $obj->value1, "commit", "yay";
_check_object($obj);

## if something goes wrong writing the second partition we roll back
## the first one
## set up a trap:
my $second_driver = Ingredient2Recipe->driver->drivers->[-1];
my $dbh = $second_driver->dbh;
my $sth = $dbh->prepare("insert into ingredient2recipe (ingredient_id, recipe_id, value1) values (199, 199, 'tada')");
$sth->execute;
$sth->finish;

Data::ObjectDriver::BaseObject->begin_work();
$obj = Ingredient2Recipe->new;
$obj->ingredient_id(199);
$obj->recipe_id(199);
$obj->value1("test");
eval { $obj->insert;}; 
ok $@, "rollback";
if ($@) {
    Data::ObjectDriver::BaseObject->rollback();
}
else {
    Data::ObjectDriver::BaseObject->commit();
}
# since on_lookup use the first driver this should be undef
my $void = Ingredient2Recipe->lookup(199);
is $void, undef, "rolled back";

## Object remove()
$obj = Ingredient2Recipe->new;
$obj->ingredient_id(4);
$obj->recipe_id(42);
$obj->replace;

my $pk = $obj->primary_key;
is $pk, 42;
my $obj2 = Ingredient2Recipe->lookup($pk);
ok $obj2, "got our object back";
$obj2->remove;

$obj = Ingredient2Recipe->lookup($pk);
is $obj, undef, "Object deleted";
($obj) = Ingredient2Recipe->search({ingredient_id => 4});
is $obj, undef, "the other driver has deleted it too";

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
