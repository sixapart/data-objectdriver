# $Id$

use strict;

use Data::Dumper;
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

plan tests => 19;

use Recipe;
use Ingredient;

setup_dbs({
    global => [ qw( recipes ingredients ) ],
});

my $r = Recipe->new;
$r->title("Spaghetti");
$r->save;

my $i = Ingredient->new;
$i->name("Oregano");
$i->recipe_id($r->recipe_id);
ok( $i->save, "Saved first ingredient" );

$i = Ingredient->new;
$i->name("Salt");
$i->recipe_id($r->recipe_id);
ok( $i->save, "Saved second ingredient" );

$i = Ingredient->new;
$i->name("Onion");
$i->recipe_id($r->recipe_id);
ok( $i->save, "Saved third ingredient" );

my $load_count = 0;
my $trigger = sub { $load_count++ };
Ingredient->add_trigger( 'post_load', $trigger );

$load_count = 0;
Ingredient->driver->clear_cache;
my $iter = Ingredient->search();
$iter->end;
is( $load_count, 3, "Default behavior: load all objects with plain search method" );

$load_count = 0;
Ingredient->driver->clear_cache;
$iter = Ingredient->search( undef, { window_size => 1 });
$i = $iter->();
$iter->end;
is( $load_count, 1, "1 ingredient loaded when window size = 1" );

$load_count = 0;
Ingredient->driver->clear_cache;
$iter = Ingredient->search( undef, { window_size => 2 });
$i = $iter->();
$iter->end;
is( $load_count, 2, "2 ingredients loaded" );

$load_count = 0;
Ingredient->driver->clear_cache;
$iter = Ingredient->search( undef, { window_size => 1, sort => "name", direction => "asc" });
my $i1 = $iter->();
ok($i1, "First row from windowed select returned");
is( $i1->name, "Onion", "Name is 'Onion'" );
my $i2 = $iter->();
ok( $i2, "Second row from windowed select returned");
is( $i2->name, "Oregano", "Name is 'Oregano'" );
ok( $iter->(), "Third row from windowed select returned" );
ok( ! $iter->(), "No more rows, which is okay" );
is( $load_count, 3, "3 objects loaded");
$iter->end;

$load_count = 0;
Ingredient->driver->clear_cache;
$iter = Ingredient->search( undef, { window_size => 5, limit => 2, sort => "name", direction => "asc" });
$i1 = $iter->();
ok($i1, "First row from windowed select returned");
is( $i1->name, "Onion", "Name is 'Onion'" );
$i2 = $iter->();
ok( $i2, "Second row from windowed select returned");
is( $i2->name, "Oregano", "Name is 'Oregano'" );
ok( !$iter->(), "No third row; limit argument respected" );
is( $load_count, 2, "2 objects loaded; limit argument respected");
$iter->end;

teardown_dbs(qw( global ));

print Dumper( Data::ObjectDriver->profiler->query_log ) if $ENV{DOD_PROFILE};
