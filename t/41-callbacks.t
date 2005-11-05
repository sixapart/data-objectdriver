# $Id$

use strict;

use lib 't/lib';

require 't/lib/db-common.pl';

use Test::More;
unless (eval { require DBD::SQLite }) {
    plan skip_all => 'Tests require DBD::SQLite';
}
plan tests => 11;

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


## test pre_save
{
    my $wine = Wine->new;
    $wine->name("Saumur Champigny, Le Grand Clos 2001");
    $wine->rating(4);

    my $ran_callback = 0;
    my $test_pre_save = sub {
        is scalar(@_), 1, 'callback received correct number of parameters';
        
        my ($saving_wine) = @_;
        ## This is not the original object, so we can't test it that way.
        isa_ok $saving_wine, 'Wine', 'callback received correct kind of object';
        ok $saving_wine->name eq "Saumur Champigny, Le Grand Clos 2001"
            && $saving_wine->rating == 4
            && !defined($saving_wine->id), 'callback received object with right data';

        ## Change rating to test immutability of original.
        $saving_wine->rating(5);

        $ran_callback++;
        return;
    };

    Wine->add_trigger('pre_save', $test_pre_save);

    $wine->save or die "Object did not save successfully";

    is $ran_callback, 1, 'callback ran exactly once';
    ok defined $wine->id, 'object did receive ';
    
    my $saved_wine = Wine->lookup($wine->id)
        or die "Object just saved could not be retrieved successfully";
    is $saved_wine->rating, 5, 'change in callback did change saved data';
    is $wine->rating, 4, 'change in callback did not change original object';
};


## test post_load
{
    ## ...but how do we remove the pre_save callback?
};


teardown_dbs(qw( global ));

1;

