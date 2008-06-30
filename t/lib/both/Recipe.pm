# $Id$

package Recipe;
use strict;
use base qw( Data::ObjectDriver::BaseObject );

use Cache::Memory;
use Data::ObjectDriver::Driver::Cache::Cache;
use Data::ObjectDriver::Driver::DBI;

__PACKAGE__->install_properties({
    columns => [ 'recipe_id', 'partition_id', 'title' ],
    datasource => 'recipes',
    primary_key => 'recipe_id',
    driver => Data::ObjectDriver::Driver::Cache::Cache->new(
        cache => Cache::Memory->new,
        fallback => Data::ObjectDriver::Driver::DBI->new(
            dsn      => 'dbi:SQLite:dbname=global.db',
            reuse_dbh => 1,
        ),
    ),
});

my %drivers;
__PACKAGE__->has_partitions(
    number => 2,
    get_driver => sub {
        my $cluster = shift;
        my $driver = $drivers{$cluster} ||= 
            Data::ObjectDriver::Driver::DBI->new(
                dsn => 'dbi:SQLite:dbname=cluster' . $cluster . '.db',
                reuse_dbh => 1,
                @_,
            );
        return $driver;
    },
);

sub ingredients {
    my $recipe = shift;
    unless (exists $recipe->{__ingredients}) {
        $recipe->{__ingredients} = [
                Ingredient->search({ recipe_id => $recipe->recipe_id })
            ];
    }
    $recipe->{__ingredients};
}

sub deflate {
    my $recipe = shift;
    my $deflated = $recipe->SUPER::deflate;
    $deflated->{ingredients} = [
            map $_->deflate, @{ $recipe->ingredients }
        ];
    $deflated;
}

sub inflate {
    my $class = shift;
    my($deflated) = @_;
    my $recipe = $class->SUPER::inflate($deflated);
    $recipe->{__ingredients} = [
            map Ingredient->inflate($_), @{ $deflated->{ingredients} }
        ];
    $recipe;
}

1;
