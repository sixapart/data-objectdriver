# $Id$

use strict;

use lib 't/lib';
use lib 't/lib/cached';

require 't/lib/db-common.pl';

use Benchmark qw(:all);
use User;

setup_dbs({
    global => [ qw( user ) ],
});

my $how_many = shift || 10_000;
my @recipes;
=cut
for (1..$how_many) {
    my $recipe = Recipe->new;
    $recipe->title("recipe $_");
    $recipe->insert;
}
=cut

## generate some data
my $data = { map { $_ => $_ } @{ User->properties->{columns} } };
$data->{user_id} = int rand 100000;

my @users;
my $i;
timethis( $how_many, sub {
    push @users, User->inflate({ columns => $data });
});

sub DESTROY { teardown_dbs(qw( global )); }
