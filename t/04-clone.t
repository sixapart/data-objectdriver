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

plan tests => 29;

use Wine;
use Recipe;
use Ingredient;

setup_dbs({
    global => [ qw( wines recipes ingredients) ],
});

sub test_basic_cloning {
    my $method = shift;

    my $old ='Cul de Veau à la Sauge'; # tastes good !
    my $new ='At first my tests ran on Recipe, sorry (Yann)';
    my $w = Wine->new;
    $w->name($old);
    ok $w->save;
    my $id = $w->id;
    ok $id, 'Saved Wine has an id';

    my $clone = $w->$method();

    ok defined $clone, 'Successfully cloned';
    isnt $w, $clone, 'Clone is not reference to the original';
    is $w->name, $clone->name, 'Clone has the same name';

    $clone->name($new);
    isnt $w->name, $clone->name, 'Changing clone does not affect the original';

    my $clone2 = $w->clone;
    isnt $w, $clone2, 'Second clone is not a reference to the original';
    isnt $clone, $clone2, 'Second clone is not a reference to the first clone';
}

test_basic_cloning('clone');
test_basic_cloning('clone_all');

# clone pk behavior
{
    my $w = Wine->new;
    $w->name('Cul de Veau à la Sauge');
    ok $w->save;
    ok $w->id, 'Saved original wine received an id';

    my $clone = $w->clone;

    ok !defined $clone->id, 'Basic clone has no id';

    ok $clone->save, 'Basic clone could be saved';
    is $clone->name, 'Cul de Veau à la Sauge';
    is $clone->is_changed('name'), '', "This is documentation ;-)";
    $clone->refresh;
    is $clone->name, 'Cul de Veau à la Sauge';
    ok defined $clone->id, 'Basic clone has an id after saving';
    isnt $w->id, $clone->id, q(Basic clone's id differs from original's id);
}

# clone_all pk behavior
{
    my $w = Wine->new;
    $w->name('Cul de Veau à la Sauge');
    ok $w->save;
    ok $w->id, 'Saved original wine received an id';

    my $clone = $w->clone_all;

    ok defined $clone->id, 'Full clone has an id';
    is $w->id, $clone->id, q(Full clone's id matches original's id);
}

sub DESTROY { teardown_dbs(qw( global )); }

