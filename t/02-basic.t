# $Id: 01-col-inheritance.t 989 2005-09-23 19:58:01Z btrott $

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

plan tests => 67;

use Wine;
use Recipe;
use Ingredient;

setup_dbs({
    global => [ qw( wines recipes ingredients) ],
});

# method installation
{ 
    my $w = Wine->new;
    ok $w->name("name");
    ok $w->has_column("name");
    ok ! $w->has_column("inexistent");
    dies_ok { $w->inexistent("hell") } "dies on setting inexistent column : 'inexistent()'";
    dies_ok { $w->column('inexistent') } "dies on setting inexistent column : 'column()'";
}

# refresh
{ 
    my $old ='Cul de Veau à la Sauge'; # tastes good !
    my $new ='At first my tests ran on Recipe, sorry (Yann)';
    my $w1 = Wine->new;
    $w1->name($old);
    ok $w1->save;
    my $id = $w1->id;
    
    my $w2 = Wine->lookup($id);
    $w2->name($new);
    $w2->save;
    cmp_ok $w1->name, 'eq', $old, "Old name not updated...";
    cmp_ok $w2->name, 'eq', $new, "... but new name is set";

    $w1->refresh;

    cmp_ok $w1->name, 'eq', $new, "Refreshed";
    is $w1->remove, 1, 'Remove correct number of rows';
    is $w2->remove, '0E0', 'Remove correct number of rows';
}

# Constructor testing
{
    my $w = Wine->new(name=>'Mouton Rothschild', rating=> 4);

    ok ($w, 'constructed a new Wine');
    is ($w->name, 'Mouton Rothschild', 'name constructor');
    is ($w->rating, 4, 'rating constructor');
}

# lookup with hash (single pk) 
{
    my $w = Wine->new;
    $w->name("Veuve Cliquot");
    $w->save;
    my $id = $w->id;
    undef $w;

    # lookup test
    lives_ok { $w = Wine->lookup({ id => $id })} "Alive !";
    cmp_ok $w->name, 'eq', 'Veuve Cliquot', "simple data test";

    ok $w;
    is $w->remove, 1, 'Remove correct number of rows';
}

## lookup_multi give a sorted result set 
{

    my @ids;
    for (1 .. 14) {
        my $w = Wine->new(name => "wine-$_");
        $w->save;
        push @ids, $w->id;
    }
    if (eval { require List::Util }) {
        @ids = List::Util::shuffle @ids;
    } else {
        @ids = reverse @ids;
    }
    my @got = map { $_->id } @{ Wine->lookup_multi(\@ids) };
    is_deeply \@got, \@ids, "Sorted result set";
}

# lookups with hash (multiple pk) 
{
    my $r = Recipe->new;
    $r->title("Good one");
    ok $r->save;
    my $rid = $r->recipe_id;
    ok $rid;

    my $i = Ingredient->new;
    $i->recipe_id($rid);
    $i->quantity(1);
    $i->name('Chouchenn');
    ok $i->save;
    my $id = $i->id;
    undef $i;
    
    # lookup test
    dies_ok  { $i = Ingredient->lookup({ id => $id, quantity => 1 })} "Use Search !";
    lives_ok { $i = Ingredient->lookup({ id => $id, recipe_id => $rid })} "Alive";
    cmp_ok $i->name, 'eq', 'Chouchenn', "simple data test";
    
    # lookup_multi with hash (multiple pk) 
    lives_ok { $i = Ingredient->lookup_multi(
        [{ id => $id, recipe_id => $rid }])
    } "Alive";
    is scalar @$i, 1;

    # add a second ingredient
    my $i2 = Ingredient->new(
        recipe_id => $rid,
        quantity  => 1,
        name      => 'honey',
    );
    $i2->save;
    my $id2 = $i2->id;
    lives_ok { $i = Ingredient->lookup_multi(
        [{ id => $id, recipe_id => $rid }, { id => $id2, recipe_id => $rid } ])
    } "Alive";
    is scalar @$i, 2;

    is $r->remove, 1, 'Remove correct number of rows';
    is $i->[0]->remove, 1, 'Remove correct number or rows';
    is $i->[1]->remove, 1, 'Remove correct number or rows';
}


# replace
{ 
    my $r = Recipe->new;
    $r->title("to replace");
    ok $r->replace;
    ok(my $rid = $r->recipe_id);
    my $r2 = Recipe->new;
    $r2->recipe_id($rid);
    $r2->title('new title');
    ok $r2->replace;
    
    ## check
    $r = Recipe->lookup($rid);
    is $r->title, 'new title';
    
    $r2 = Recipe->new;
    $r2->recipe_id($rid);
    ok $r2->replace;

    ## check
    $r = Recipe->lookup($rid);
    is $r->title, undef;
}

# let's test atomicity of replace
{
    my $r = Recipe->new;
    $r->title("to replace");
    $r->insert;

    ## too long title:
    # Oh! right it's a feature :( 
    # http://www.sqlite.org/faq.html#q3
    #$r->title(join '', ("0123456789" x 6));
    #dies_ok { $r->replace };
    #$r->refresh;
    my $id = $r->recipe_id;
    $r->title('replaced');
    $r->recipe_id("lamer");
    dies_ok { $r->replace };
    $r = Recipe->lookup($id);
    ok $r;
    is $r->title, "to replace";
    
    # emulate a driver which doesn't support REPLACE INTO
    { 
        no warnings 'redefine';
        local *Data::ObjectDriver::Driver::DBD::SQLite::can_replace = sub { 0 };
        $r->title('replaced');
        $r->recipe_id("lamer");
        dies_ok { $r->replace };
        $r = Recipe->lookup($id);
        ok $r;
        is $r->title, "to replace";
        # emulate a driver which doesn't support REPLACE INTO
    }
}


# is_changed interface 
{
    my $w = Wine->new;
    $w->name("Veuve Cliquot");
    $w->save;
    ok ! $w->is_changed;
    $w->name("veuve champenoise");
    ok $w->is_changed;
    ok $w->is_changed('name');
    ok ! $w->is_changed('content');
}

# Remove counts
{
    # Clear out the wine table
    ok (Wine->remove(), 'delete all from Wine table');

    is (Wine->remove({name=>'moooo'}), 0E0, 'No rows deleted');
    my @bad_wines = qw(Thunderbird MadDog Franzia);
    foreach my $name (@bad_wines) {
        my $w = Wine->new;
        $w->name($name);
        ok $w->save, "Saving bad_wine $name";
    }
    is (Wine->remove(), scalar(@bad_wines), 'removing all bad wine');

    # Do it again with direct remove from the DB
    foreach my $name (@bad_wines) {
        my $w = Wine->new;
        $w->name($name);
        ok $w->save, "Saving bad_wine $name";
    }
    # note sqlite is stupid and doesn't return the number of affected rows
    is (Wine->remove({}, { nofetch => 1 }), '0E0', 'removing all bad wine');
}

# different utilities
{
    my $w1 = Wine->new;
    $w1->name("Chateau la pompe");
    $w1->insert;

    my $w3 = Wine->new;
    $w3->name("different");
    $w3->insert;
    
    my $w2 = Wine->lookup($w1->id);
    ok  $w1->is_same($w1);
    ok  $w2->is_same($w1);
    ok  $w1->is_same($w2);
    ok !$w1->is_same($w3);
    ok !$w3->is_same($w2);

    like $w1->pk_str, qr/\d+/;
}

# Test the new flag for persistent store insertion
{
    my $w = Wine->new(name => 'flag test', rating=> 4);
    ok !$w->object_is_stored, "this object needs to be saved!";
    $w->save;
    ok $w->object_is_stored, "this object is no saved";
    my $w2 = Wine->lookup( $w->id );
    ok $w2->object_is_stored, "an object fetched from the database is by definition NOT ephemeral";
}

sub DESTROY { teardown_dbs(qw( global )); }

