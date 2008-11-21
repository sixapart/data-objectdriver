# $Id$

use strict;

use lib 't/lib';
use lib 't/lib/both';

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

plan tests => 18;

use Recipe;
use Ingredient;

setup_dbs({
    global   => [ qw( recipes ) ],
    cluster1 => [ qw( ingredients ) ],
    cluster2 => [ qw( ingredients ) ],
});

$Data::ObjectDriver::PROFILE = 1;

my $recipe = Recipe->new;
$recipe->title('Cake');
$recipe->save;

## disable caching because it makes the test more complicate
## to understand. Indeed inflate and deflate generates additional
## queries difficult to account for
use Data::ObjectDriver::Driver::Cache::Cache;
Data::ObjectDriver::Driver::Cache::Cache->Disabled(1);

my $profiler = Data::ObjectDriver->profiler;

my $stats = $profiler->statistics;
is $stats->{'DBI:total_queries'}, 1;
is $stats->{'DBI:query_insert'}, 1;

my $log = $profiler->query_log;
isa_ok $log, 'ARRAY';
is scalar(@$log), 1;
like $log->[0], qr/^\s*INSERT INTO recipe/;

my $frequent = $profiler->query_frequency;
isa_ok $frequent, 'HASH';
my $sql = (keys %$frequent)[0];
like $sql, qr/^\s*INSERT INTO recipe/;
is $frequent->{$sql}, 1;

Data::ObjectDriver->profiler->reset;

$stats = $profiler->statistics;
is scalar(keys %$stats), 0;

$recipe = Recipe->lookup($recipe->recipe_id);

$stats = $profiler->statistics;
is $stats->{'DBI:total_queries'}, 1;
is $stats->{'DBI:query_select'}, 1;

$recipe->title('Brownies');
$recipe->save;

$stats = $profiler->statistics;
is $stats->{'DBI:total_queries'}, 3;
is $stats->{'DBI:query_select'}, 2;
is $stats->{'DBI:query_update'}, 1;

$recipe->title('Flan');
$recipe->save;

$frequent = $profiler->query_frequency;
is $frequent->{"SELECT 1 FROM recipes WHERE (recipes.recipe_id = ?)"}, 2;

is $profiler->total_queries, 5;

SKIP: {
        my $simpletable = eval { require Text::SimpleTable };
        skip "Text::SimpleTable not installed", 2 unless $simpletable;

        like $profiler->report_query_frequency, qr/FROM recipes/;
        like $profiler->report_queries_by_type, qr/SELECT/;
};

sub DESTROY { teardown_dbs(qw( global cluster1 cluster2 )); }
