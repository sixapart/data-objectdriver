# $Id$

package Recipe;
use strict;
use base qw( Data::ObjectDriver::BaseObject );

use Cache::Memory;
use Data::ObjectDriver::Driver::Cache::Cache;
use Data::ObjectDriver::Driver::DBI;

__PACKAGE__->install_properties({
    columns => [ 'id', 'cluster_id', 'title' ],
    datasource => 'recipes',
    primary_key => 'id',
    driver => Data::ObjectDriver::Driver::Cache::Cache->new(
        cache => Cache::Memory->new,
        fallback => Data::ObjectDriver::Driver::DBI->new(
            dsn      => 'dbi:SQLite:dbname=global.db',
        ),
    ),
});

sub insert {
    my $obj = shift;
    ## Choose a cluster for this recipe. This isn't a very solid way of
    ## doing this, but it works for testing.
    $obj->cluster_id(int(rand 2) + 1);
    $obj->SUPER::insert(@_);
}

sub ingredients {
    my $recipe = shift;
    unless (exists $recipe->{__ingredients}) {
        $recipe->{__ingredients} = [
                Ingredient->search({ recipe_id => $recipe->id })
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
