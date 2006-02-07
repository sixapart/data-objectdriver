# $Id$

use strict;

use lib 't/lib';
use lib 't/lib/cached';

require 't/lib/db-common.pl';

use Test::More;
use Test::Exception;
BEGIN {
    unless (eval { require DBD::SQLite }) {
        plan skip_all => 'Tests require DBD::SQLite';
    }
    unless (eval { require Cache::Memory }) {
        plan skip_all => 'Tests require Cache::Memory';
    }
}

plan tests => 8;

use Wine;
use Recipe;
use Ingredient;

setup_dbs({
    global => [ qw( wines recipes ingredients) ],
});

## TODO: test primary_key and has_primary_key

# simple class pk fields
{
    isa_ok(Wine->primary_key_tuple(), 'ARRAY', q(Wine's primary key tuple is an arrayref));
    is_deeply(Wine->primary_key_tuple(), ['id'], q(Wine's primary key tuple contains the string 'id'));
}

# complex class pk fields
{
    isa_ok(Ingredient->primary_key_tuple, 'ARRAY', q(Ingredient's primary key tuple is an arrayref));
    is_deeply(Ingredient->primary_key_tuple, ['recipe_id', 'id'], q(Ingredient instance's primary key tuple contains 'recipe_id' and 'id'));
}

# simple instance pk fields
{
    my $w = Wine->new;
    isa_ok $w->primary_key_tuple, 'ARRAY', q(Wine instance's primary key tuple is an arrayref);
    is_deeply $w->primary_key_tuple, ['id'], q(Wine instance's primary key tuple contains the string 'id');
}

# complex instance pk fields
{
    my $i = Ingredient->new;
    is ref $i->primary_key_tuple, 'ARRAY', q(Ingredient instance's primary key tuple is an arrayref);
    is_deeply $i->primary_key_tuple, ['recipe_id', 'id'], q(Ingredient instance's primary key tuple contains 'recipe_id' and 'id');
}

teardown_dbs(qw( global ));

