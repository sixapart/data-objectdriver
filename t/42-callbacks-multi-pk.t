# $Id: 41-callbacks.t 1037 2005-11-25 14:51:09Z ykerherve $

use strict;

use lib 't/lib/partitioned';

require 't/lib/db-common.pl';

use Test::More;
unless (eval { require DBD::SQLite }) {
    plan skip_all => 'Tests require DBD::SQLite';
}
plan tests => 13;

setup_dbs({
    global   => [ qw( recipes ) ],
    cluster1 => [ qw( ingredients ) ],
    cluster2 => [ qw( ingredients ) ],
});

use Recipe;
use Ingredient;

## test pre_save
{
    my $title    = "Crême brûlée à la pistache";
    my $name     = "Eggs";
    my $quantity = 10;

    my $recipe = Recipe->new;
    $recipe->title($title);
    $recipe->save;

    my $ingredient = Ingredient->new;
    $ingredient->recipe_id($recipe->recipe_id);
    $ingredient->name($name);
    $ingredient->quantity($quantity);

    ## it makes no sense to test if have the wrong init. cond.
    isa_ok $ingredient->primary_key_tuple, 'ARRAY';
    ok($recipe->partition_id, 'Recipe assigned to a cluster');

    my $ran_callback = 0;
    my $test_pre_save = sub {
        is scalar(@_), 2, 'callback received correct number of parameters';
        
        my ($saving) = @_;
        ## This is not the original object, so we can't test it that way.
        isa_ok $saving, 'Ingredient', 'callback received correct kind of object';
        cmp_ok $saving->name, 'eq',  $name, $name;
        cmp_ok $saving->quantity, '==', $quantity, 'quantity';
        ok !defined($saving->id), 'callback received object with right data';

        ## Change rating to test immutability of original.
        $saving->quantity($quantity * 2);

        $ran_callback++;
        return;
    };

    ## Add callback
    Ingredient->add_trigger('pre_save', $test_pre_save);
    
    ## Call the save that should trigger the callback
    $ingredient->save or die "Object did not save successfully";

    is $ran_callback, 1, 'callback ran exactly once';
    ok defined $ingredient->primary_key, 'object did receive a pk';
    
    my $saved = Ingredient->lookup($ingredient->primary_key)
        or die "Object just saved could not be retrieved successfully";
    is $saved->quantity, $quantity * 2, 'change in callback did change saved data';
    is $ingredient->quantity, $quantity, 'change in callback did not change original object';
    $ingredient->refresh;
    is $ingredient->quantity, $quantity * 2, 'refreshed worked';
    ok($ingredient->recipe_id, 'Ingredient assigned to a recipe');
};


teardown_dbs(qw( global ));

1;
