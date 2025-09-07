# $Id$

use strict;
use warnings;

use lib 't/lib';
use lib 't/lib/cached';
use Data::ObjectDriver::SQL;
use Test::More tests => 1;
use DodTestUtil;

BEGIN { DodTestUtil->check_driver }

subtest 'reuse prepared statement(complex)' => sub {
    require Recipe;
    require Ingredient;

    subtest 'case1' => sub {
        my $stmt = Recipe->driver->prepare_statement(
            'Recipe', [
                { title => 'title1' },
                {
                    recipe_id => {
                        op    => 'IN',
                        value => Ingredient->driver->prepare_statement(
                            'Ingredient', 
                            { col1 => { op => 'LIKE', value => 'sub1', escape => '!' } },
                            { fetchonly => ['id'], limit => 2 }) }
                },
            ],
            { limit => 4 });

        my $expected = sql_normalize(<<'EOF');
SELECT 
    recipes.recipe_id, recipes.title
FROM
    recipes
WHERE
    ((title = ?))
    AND
    ((recipe_id IN (SELECT ingredients.id FROM ingredients WHERE (ingredients.col1 LIKE ? ESCAPE '!') LIMIT 2)))
LIMIT 4
EOF
        is sql_normalize($stmt->as_sql), sql_normalize($expected), 'right sql';
        is_deeply($stmt->{bind}, ['title1', 'sub1'], 'right bind values');
    };

    subtest 'case2' => sub {
        my $stmt = Recipe->driver->prepare_statement(
            'Recipe',
            [[
                    { title => 'title1' },
                    '-or',
                    {
                        recipe_id => {
                            op    => 'IN',
                            value => Ingredient->driver->prepare_statement(
                                'Ingredient', [
                                    { col1 => { op => 'LIKE', value => 'sub1', escape => '!' } },
                                    { col2 => { op => 'LIKE', value => 'sub2', escape => '!' } },
                                ],
                                { fetchonly => ['id'], limit => 2 }) }
                    },
                    '-or',
                    { title => 'title2' },
                ],
                { title3 => 'title3' },
            ],
            { limit => 4 });

        my $expected = sql_normalize(<<'EOF');
SELECT
    recipes.recipe_id, recipes.title
FROM
    recipes
WHERE
    (
        ((title = ?))
        OR
        ((recipe_id IN (
            SELECT ingredients.id
            FROM ingredients
            WHERE ((col1 LIKE ? ESCAPE '!')) AND ((col2 LIKE ? ESCAPE '!'))
            LIMIT 2
        )))
        OR
        ((title = ?))
    ) AND (
        (title3 = ?)
    )
LIMIT 4
EOF
        is sql_normalize($stmt->as_sql), sql_normalize($expected), 'right sql';
        is_deeply($stmt->{bind}, ['title1', 'sub1', 'sub2', 'title2', 'title3'], 'right bind values');
    };
};

sub sql_normalize {
    my $sql = shift;
    $sql =~ s{\s+}{ }g;
    $sql =~ s{\( }{(}g;
    $sql =~ s{ \)}{)}g;
    $sql =~ s{([\(\)]) ([\(\)])}{$1$2}g;
    $sql;
}

sub ns { Data::ObjectDriver::SQL->new }
