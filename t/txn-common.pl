# $Id: db-common.pl 58 2006-05-04 00:04:10Z sky $

use strict;
use Test::More;

#diag "executing common transaction tests";
use Data::ObjectDriver::BaseObject;

## testing basic rollback
{
    Data::ObjectDriver::BaseObject->begin_work;

    my $recipe = Recipe->new;
    $recipe->title('gratin dauphinois');
    ok($recipe->save, 'Object saved successfully');
    ok(my $recipe_id = $recipe->recipe_id, 'Recipe has an ID');
    is($recipe->title, 'gratin dauphinois', 'Title is set');

    my $ingredient = Ingredient->new;
    $ingredient->recipe_id($recipe->recipe_id);
    $ingredient->name('cheese');
    $ingredient->quantity(10);
    ok($ingredient->save, 'Ingredient saved successfully');
    ok(my $ingredient_pk = $ingredient->primary_key, 'Ingredient has an ID');
    ok($ingredient->id, 'ID is defined');
    is($ingredient->name, 'cheese', 'got a name for the ingredient');

    #use YAML; warn Dump (Data::ObjectDriver::BaseObject->txn_debug);
    Data::ObjectDriver::BaseObject->rollback;
    
    ## check that we don't have a trace of all the good stuff we cooked
    is(Recipe->lookup($recipe_id), undef, "no trace of object");
    is(eval { Ingredient->lookup($ingredient_pk) }, undef, "no trace of object");
    is(Recipe->lookup_multi([ $recipe_id ])->[0], undef);
}

## testing basic commit
{
    Data::ObjectDriver::BaseObject->begin_work;

    my $recipe = Recipe->new;
    $recipe->title('gratin dauphinois');
    ok($recipe->save, 'Object saved successfully');
    ok(my $recipe_id = $recipe->recipe_id, 'Recipe has an ID');
    is($recipe->title, 'gratin dauphinois', 'Title is set');

    my $ingredient = Ingredient->new;
    $ingredient->recipe_id($recipe->recipe_id);
    $ingredient->name('cheese');
    $ingredient->quantity(10);
    ok($ingredient->save, 'Ingredient saved successfully');
    ok(my $ingredient_pk = $ingredient->primary_key, 'Ingredient has an ID');
    ok($ingredient->id, 'ID is defined');
    is($ingredient->name, 'cheese', 'got a name for the ingredient');

    Data::ObjectDriver::BaseObject->commit;
    
    ## check that we don't have a trace of all the good stuff we cooked
    ok(Recipe->lookup($recipe_id), "still here");
    ok(Ingredient->lookup($ingredient_pk), "still here");
    ok defined Recipe->lookup_multi([ $recipe_id ])->[0];
    
    ## and now test a rollback of a remove
    Data::ObjectDriver::BaseObject->begin_work;
    $ingredient->remove;
    Data::ObjectDriver::BaseObject->rollback;
    ok(Ingredient->lookup($ingredient_pk), "still here");
    
    ## finally let's delete it
    Data::ObjectDriver::BaseObject->begin_work;
    $ingredient->remove;
    Data::ObjectDriver::BaseObject->commit;
    ok(! Ingredient->lookup($ingredient_pk), "finally deleted");
}

sub warns_ok (&;$) {
    my ($sub, $msg) = @_;

    my $warn = 0;
    local $SIG{__WARN__} = sub { $warn++ };
    $sub->();

    $warn ? pass($msg) : fail($msg);
}

## nested transactions
{
    ## if there is no transaction active this will just warn
    is( Data::ObjectDriver::BaseObject->txn_active, 0);
    warns_ok { Data::ObjectDriver::BaseObject->commit() }
        'committing with no active transaction caused warning';
    is( Data::ObjectDriver::BaseObject->txn_active, 0);
    
    ## do a commit in the end
    Data::ObjectDriver::BaseObject->begin_work;
    is( Data::ObjectDriver::BaseObject->txn_active, 1);

    my $recipe = Recipe->new;
    $recipe->title('lasagnes');
    ok($recipe->save, 'Object saved successfully');

    warns_ok { Data::ObjectDriver::BaseObject->begin_work() }
        'beginning new transaction with a transaction already open '
        . 'causes warning';
    warns_ok { Data::ObjectDriver::BaseObject->begin_work() }
        'beginning new transaction with two transactions already open '
        . 'causes warning';
    is( Data::ObjectDriver::BaseObject->txn_active, 3);

    
    my $ingredient = Ingredient->new;
    $ingredient->recipe_id($recipe->recipe_id);
    $ingredient->name("pasta");
    ok $ingredient->insert;

    Data::ObjectDriver::BaseObject->rollback;
    Data::ObjectDriver::BaseObject->commit;
    Data::ObjectDriver::BaseObject->commit;
    is( Data::ObjectDriver::BaseObject->txn_active, 0);
    
    $recipe = Recipe->lookup($recipe->primary_key);
    $ingredient = Ingredient->lookup($ingredient->primary_key);
    ok $recipe, "got committed";
    ok $ingredient, "got committed";
    is $ingredient->name, "pasta";
    
    ## now test the same thing with a rollback in the end
    Data::ObjectDriver::BaseObject->begin_work;

    $recipe = Recipe->new;
    $recipe->title('lasagnes');
    ok($recipe->save, 'Object saved successfully');

    warns_ok { Data::ObjectDriver::BaseObject->begin_work() }
        'beginning new transaction with a transaction already open '
        . 'still causes warning';
    
    $ingredient = Ingredient->new;
    $ingredient->recipe_id($recipe->recipe_id);
    $ingredient->name("more layers");
    ok $ingredient->insert;

    Data::ObjectDriver::BaseObject->commit;
    Data::ObjectDriver::BaseObject->rollback;
    
    $recipe = Recipe->lookup($recipe->primary_key);
    $ingredient = eval { Ingredient->lookup($ingredient->primary_key) };
    ok ! $recipe, "rollback";
    ok ! $ingredient, "rollback";
}

1;
