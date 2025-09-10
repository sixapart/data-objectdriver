# $Id$

use strict;
use warnings;

use lib 't/lib';
use lib 't/lib/cached';
use Data::ObjectDriver::SQL;
use Test::More tests => 3;
use DodTestUtil;

BEGIN { DodTestUtil->check_driver }

use Recipe;
use Ingredient;

subtest 'as_subquery' => sub {
    my $stmt = Ingredient->driver->prepare_statement('Ingredient', { col1 => 'sub1' }, { fetchonly => ['id'] });

    is(sql_normalize($stmt->as_subquery), sql_normalize(<<'EOF'), 'right sql');
(SELECT ingredients.id FROM ingredients WHERE (ingredients.col1 = ?))
EOF
    is_deeply($stmt->{bind}, ['sub1'], 'right bind values');

    $stmt->as('mysubquery');

    is(sql_normalize($stmt->as_subquery), sql_normalize(<<'EOF'), 'right sql');
(SELECT ingredients.id FROM ingredients WHERE (ingredients.col1 = ?)) AS mysubquery
EOF
};

subtest 'subquery in select clause' => sub {

    subtest 'case1' => sub {
        my $stmt = Recipe->driver->prepare_statement('Recipe', [{ title => 'title1' }, {}], {});
        $stmt->add_select(Ingredient->driver->prepare_statement(
            'Ingredient',
            [{ recipe_id => \'= recipes.recipe_id' }, { col1 => 'sub1' }], { fetchonly => ['id'] }));

        my $expected = sql_normalize(<<'EOF');
SELECT
    recipes.recipe_id,
    recipes.title,
    (
        SELECT ingredients.id
        FROM ingredients
        WHERE ((recipe_id = recipes.recipe_id)) AND ((col1 = ?))
    )
FROM recipes
WHERE ((title = ?))
EOF

        is sql_normalize($stmt->as_sql), sql_normalize($expected), 'right sql';
        is_deeply($stmt->{bind}, ['title1', 'sub1'], 'right bind values');
    };

    subtest 'with alias' => sub {
        my $stmt = Recipe->driver->prepare_statement('Recipe', [{}, {}], {});
        my $subquery = Ingredient->driver->prepare_statement(
            'Ingredient',
            [{ recipe_id => \'= recipes.recipe_id' }], { fetchonly => ['id'] });
        $subquery->as('sub_alias');
        $stmt->add_select($subquery);

        my $expected = sql_normalize(<<'EOF');
SELECT
    recipes.recipe_id,
    recipes.title,
    (
        SELECT ingredients.id
        FROM ingredients
        WHERE ((recipe_id = recipes.recipe_id))
    ) AS sub_alias
FROM recipes
EOF

        is sql_normalize($stmt->as_sql), sql_normalize($expected), 'right sql';
        is_deeply($stmt->{bind}, [], 'right bind values');
    };
};

subtest 'subquery in where clause' => sub {

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
    $sql =~ s{ $}{}g;
    $sql =~ s{\( }{(}g;
    $sql =~ s{ \)}{)}g;
    $sql =~ s{([\(\)]) ([\(\)])}{$1$2}g;
    $sql;
}

sub ns { Data::ObjectDriver::SQL->new }
