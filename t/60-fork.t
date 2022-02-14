use strict;
use warnings;
use lib 't/lib';

$Data::ObjectDriver::DEBUG = 0;
use Test::More;
use DodTestUtil;

BEGIN {
    plan skip_all => 'Not for Win32' if $^O eq 'MSWin32';

    my @requires = qw(
        Parallel::ForkManager
        Test::SharedFork
    );

    for my $module (@requires) {
        eval "require $module" or plan skip_all => "requires $module";
    }
    DodTestUtil->check_driver;
}

setup_dbs({
    global => [ qw( wines ) ],
});

use Wine;

my $wine = Wine->new;
$wine->name("Latour");
ok($wine->save, 'Object saved successfully');

my $wine_id = $wine->id;
undef $wine;
$wine = Wine->lookup($wine_id); 

ok $wine;

my $max = $ENV{DOD_TEST_MAX_FORK} || 10;
my $pm = Parallel::ForkManager->new( $ENV{DOD_TEST_WORKERS} || 4 );
$pm->run_on_finish(sub {
    my ($pid, $exit, $ident) = @_;
    ok !$exit, "pid $pid exits $exit";
});
$pm->run_on_start(sub {
    my ($pid, $ident) = @_;
    note "pid $pid starts";
});
for my $id ( 1 .. $max ) {
    my $pid = $pm->start and next;
    my $new_wine = Wine->new;
    $new_wine->name("Wine $id");
    $new_wine->begin_work;
    ok $new_wine->save, "saved wine $id";
    $new_wine->commit;

    my ($result) = Wine->result({name => 'Latour'});
    ok !$result->is_finished, "not yet finished";
    ok my $latour = $result->next, "next";
    is $latour->name => 'Latour', "found Latour";
    ok !$result->next, "no more next";
    ok $result->is_finished, "finished";

    $pm->finish;
}

$pm->wait_all_children;

pass("waited all children");

my $result = Wine->result({});
my %seen;
while( my $wine = $result->next ) {
    $seen{$wine->name} = 1;
}

ok $seen{Latour}, "seen Latour";
ok $seen{"Wine $_"}, "seen Wine $_" for 1 .. $max;

done_testing;

teardown_dbs('global');
