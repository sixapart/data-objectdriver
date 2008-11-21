# $Id$

use strict;

use lib 't/lib';

require 't/lib/db-common.pl';

use Test::More;
unless (eval { require DBD::SQLite }) {
    plan skip_all => 'Tests require DBD::SQLite';
}

plan tests => 25;

setup_dbs({
    global => [ qw( wines ) ],
});


use Wine;


## can add callbacks
{
    ok(Data::ObjectDriver::BaseObject->can('add_trigger'), 'can add triggers to BaseObject class');
    ok(My::BaseObject->can('add_trigger'), 'can add triggers to directly derived class');
    ok(Wine->can('add_trigger'), 'can add triggers to doubly derived class');
};


sub clear_triggers {
    my ($obj, $when) = @_;
    my $triggers = Class::Trigger::__fetch_triggers($obj);
    delete $triggers->{$when};
}


## test pre_save
{
    my $wine = Wine->new;
    $wine->name("Saumur Champigny, Le Grand Clos 2001");
    $wine->rating(4);

    my $ran_callback = 0;
    my $test_pre_save = sub {
        is scalar(@_), 2, 'callback received correct number of parameters';
        
        my ($saving_wine, $orig_wine) = @_;
        ## This is not the original object, so we can't test it that way.
        isa_ok $saving_wine, 'Wine', 'callback received correct kind of object';
        cmp_ok $saving_wine->name, 'eq', "Saumur Champigny, Le Grand Clos 2001";
        cmp_ok $saving_wine->rating, '==', 4, "modifiable Wine has a rating";
        ok !defined($saving_wine->id), 'modifiable Wine has no id yet';

        isa_ok $orig_wine, 'Wine', 'callback received correct kind of object';
        cmp_ok $orig_wine->name, 'eq', "Saumur Champigny, Le Grand Clos 2001";
        cmp_ok $orig_wine->rating, '==', 4, "original Wine has a rating";
        ok !defined($orig_wine->id), 'original Wine has no id yet either';

        ## Change rating of modifiable Wine to test immutability of original.
        $saving_wine->rating(5);

        $ran_callback++;
        return;
    };

    Wine->add_trigger('pre_save', $test_pre_save);

    $wine->save or die "Object did not save successfully";

    is $ran_callback, 1, 'callback ran exactly once';
    ok defined $wine->id, 'object did receive an id';
    ok ! $wine->is_changed, "not changed, since we've just saved the obj";
    
    my $saved_wine = Wine->lookup($wine->id)
        or die "Object just saved could not be retrieved successfully";
    is $saved_wine->rating, 5, 'change in callback did change saved data';
    is $wine->rating, 4, 'change in callback did not change original object';

    clear_triggers('Wine', 'pre_save');
    is $wine->remove, 1, 'Remove correct number or rows';
};

## test pre_search
{
    Wine->add_trigger('pre_search', 
        sub { return unless $_[1]->{rating}; $_[1]->{rating} = $_[1]->{rating} * 2; }
    );
    my $wine = Wine->new;
    $wine->name('I will change rating');
    $wine->rating(10);
    $wine->save;

    ($wine) = Wine->search({ rating => 5 });
    ok $wine;
    cmp_ok $wine->rating, '==', 10, "object has still the same rating";
    cmp_ok $wine->name, 'eq', 'I will change rating', "indeed";
    is $wine->remove, 1, 'Remove correct number of rows';

    clear_triggers('Wine', 'pre_search');
}

## test post_load
{
    Wine->add_trigger('post_load', 
        sub { $_[0]->rating($_[0]->rating * 3, {no_changed_flag => 1}); }
    );
    my $wine = Wine->new;
    $wine->name('I will change rating');
    $wine->rating(10);
    $wine->save;
    $wine = Wine->lookup($wine->id);
    ok $wine, "loaded";
    cmp_ok $wine->rating, '==', 30, "post_load in action";
    ok ! $wine->is_changed, "wine hasn't changed";

    clear_triggers('Wine', 'post_load');
};


sub DESTROY { teardown_dbs(qw( global )); }

1;

