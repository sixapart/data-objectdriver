# $Id$

use strict;

use lib 't/lib';
use lib 't/lib/cached';

require 't/lib/db-common.pl';

use Test::More;
use Test::Exception;
use Scalar::Util;
BEGIN {
    unless (eval { require DBD::SQLite }) {
        plan skip_all => 'Tests require DBD::SQLite';
    }
    unless (eval { require Cache::Memory }) {
        plan skip_all => 'Tests require Cache::Memory';
    }
}

plan tests => 17;

use_ok 'Data::ObjectDriver::Iterator';
my $iter;

$iter = Data::ObjectDriver::Iterator->new(sub {});

ok Scalar::Util::blessed($iter), "blessed obj";
isa_ok $iter, "CODE", "it's a subref";
isa_ok $iter, "Data::ObjectDriver::Iterator";
can_ok $iter, "next";
is $iter->next, undef;
is $iter->(), undef;

my $i = 0;
my $sub = sub {
        return undef if $i >= 10;
        return $i++;
}; 
$iter = Data::ObjectDriver::Iterator->new($sub);

is $iter->next, 0;
is $iter->(), 1;
$i = 11;
is $iter->(), undef;

$i = 2;
$iter->end(); # do nothing
is $iter->next, 2;

{
    my $sub2 = sub  { $sub->() }; # new reference
    my $iter2 = Data::ObjectDriver::Iterator->new($sub2, sub { $i = 10 });
    is $iter2->(), 3;
}
is $i, 10, "end has been called";

{
    $i = 0;
    my $sub2 = sub  { $sub->() }; # new reference
    my $iter2 = Data::ObjectDriver::Iterator->new($sub2, sub { $i = 10 });
    {
        my $sub3 = sub  { $sub->() }; # new reference
        my $iter3 = Data::ObjectDriver::Iterator->new($sub3, sub { $i = -1 });
        is $iter2->(), 0;
        is $iter3->(), 1;
    }
    is $i, -1; 
}
is $i, 10;

__END__
use Recipe;
use Ingredient;

setup_dbs({
    global => [ qw( recipes ingredients) ],
});

my $iter = $recipe->ingredients;
isa_ok $iter, "CODE", "iterator is also available";
while (my $i = $iter->()) {
    isa_ok $i, "Ingredient", "next";
}

my $r = $ingredient->recipe;
is $r->recipe_id, $recipe->recipe_id, "recipe id back using 'parent_method'";

teardown_dbs(qw( global ));
