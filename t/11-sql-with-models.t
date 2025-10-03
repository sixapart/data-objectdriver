# $Id$

use strict;
use warnings;

use lib 't/lib';
use lib 't/lib/sql';
use Test::More;
use DodTestUtil;
use Tie::IxHash;

BEGIN { DodTestUtil->check_driver }

use Blog;
use Entry;

sub ordered_hashref {
    tie my %params, Tie::IxHash::, @_;
    return \%params;
}

setup_dbs({
    global => [qw( BLOG ENTRY )],
});

my $blog1 = Blog->new(NAME => 'blog1');
$blog1->save;
my $blog2 = Blog->new(PARENT_ID => $blog1->ID, NAME => 'blog2');
$blog2->save;
my $entry11 = Entry->new(BLOG_ID => $blog1->ID, TITLE => 'title11', TEXT => 'first');
$entry11->save;
my $entry12 = Entry->new(BLOG_ID => $blog1->ID, TITLE => 'title12', TEXT => 'second');
$entry12->save;
my $entry21 = Entry->new(BLOG_ID => $blog2->ID, TITLE => 'title21', TEXT => 'first');
$entry21->save;
my $entry22 = Entry->new(BLOG_ID => $blog2->ID, TITLE => 'title22', TEXT => 'second');
$entry22->save;

subtest 'as_subquery' => sub {
    my $stmt = Blog->driver->prepare_statement('Blog', { NAME => 'foo' }, { fetchonly => ['ID'] });

    is(sql_normalize($stmt->as_subquery), sql_normalize(<<'EOF'), 'right sql');
(SELECT BLOG.ID FROM BLOG WHERE (BLOG.NAME = ?))
EOF
    is_deeply($stmt->{bind}, ['foo'], 'right bind values');

    $stmt->as('mysubquery');

    is(sql_normalize($stmt->as_subquery), sql_normalize(<<'EOF'), 'right sql');
(SELECT BLOG.ID FROM BLOG WHERE (BLOG.NAME = ?)) AS mysubquery
EOF
};

subtest 'do not aggregate bind twice' => sub {

    my $stmt     = Blog->driver->prepare_statement('Blog', { NAME => $blog1->NAME }, {});
    my $subquery = Entry->driver->prepare_statement(
        'Entry',
        ordered_hashref(BLOG_ID => \'= BLOG.ID', TEXT => 'second'),
        { fetchonly => ['ID'], limit => 1 });
    $subquery->as('SUB');
    $stmt->add_select($subquery);
    $stmt->as_sql;
    is scalar(@{ $stmt->bind }), 2;
    $stmt->as_sql;
    is scalar(@{ $stmt->bind }), 2;
};

subtest 'subquery in select clause' => sub {

    subtest 'fetch blogs and include a entry with specific text if any' => sub {
        my $stmt     = Blog->driver->prepare_statement('Blog', { NAME => $blog1->NAME }, {});
        my $subquery = Entry->driver->prepare_statement(
            'Entry',
            ordered_hashref(BLOG_ID => \'= BLOG.ID', TEXT => 'second'),
            { fetchonly => ['ID'], limit => 1 });
        $subquery->as('SUB_ALIAS');
        $stmt->add_select($subquery);

        my $expected = sql_normalize(<<'EOF');
SELECT
    BLOG.ID,
    BLOG.PARENT_ID,
    BLOG.NAME,
    (
        SELECT ENTRY.ID
        FROM ENTRY
        WHERE (ENTRY.BLOG_ID = BLOG.ID) AND (ENTRY.TEXT = ?)
        LIMIT 1
    ) AS SUB_ALIAS
FROM BLOG
WHERE (BLOG.NAME = ?)
EOF

        is sql_normalize($stmt->as_sql), sql_normalize($expected), 'right sql';
        is_deeply($stmt->{bind}, ['second', $blog1->NAME], 'right bind values');
        my @res = Blog->driver->search('Blog', $stmt);
        is scalar(@res),                             1;
        is scalar(keys %{ $res[0]{column_values} }), 4;
        is($res[0]{column_values}{ID},        $blog1->ID);
        is($res[0]{column_values}{SUB_ALIAS}, $entry12->ID);
    };

    subtest 'set alias by add_select argument' => sub {
        my $stmt     = Blog->driver->prepare_statement('Blog', { NAME => $blog1->NAME }, {});
        my $subquery = Entry->driver->prepare_statement(
            'Entry',
            ordered_hashref(BLOG_ID => \'= BLOG.ID', TEXT => 'second'),
            { fetchonly => ['ID'], limit => 1 });
        $stmt->add_select($subquery, 'SUB_ALIAS');

        my $expected = sql_normalize(<<'EOF');
SELECT
    BLOG.ID,
    BLOG.PARENT_ID,
    BLOG.NAME,
    (
        SELECT ENTRY.ID
        FROM ENTRY
        WHERE (ENTRY.BLOG_ID = BLOG.ID) AND (ENTRY.TEXT = ?)
        LIMIT 1
    ) AS SUB_ALIAS
FROM BLOG
WHERE (BLOG.NAME = ?)
EOF

        is sql_normalize($stmt->as_sql), sql_normalize($expected), 'right sql';
        is_deeply($stmt->{bind}, ['second', $blog1->NAME], 'right bind values');
        my @res = Blog->driver->search('Blog', $stmt);
        is scalar(@res),                             1;
        is scalar(keys %{ $res[0]{column_values} }), 4;
        is($res[0]{column_values}{ID},        $blog1->ID);
        is($res[0]{column_values}{SUB_ALIAS}, $entry12->ID);
    };
};

subtest 'select_map used in add_having' => sub {
    my $stmt = Entry->driver->prepare_statement('Entry', {}, {});
    $stmt->add_select('count(*)', 'COUNT');
    $stmt->group({column => 'BLOG_ID'});
    $stmt->add_having(COUNT => 2);
    is sql_normalize($stmt->as_sql), sql_normalize(<<'EOF');
SELECT ENTRY.ID, ENTRY.BLOG_ID, ENTRY.TITLE, ENTRY.TEXT, count(*) COUNT
FROM ENTRY
GROUP BY BLOG_ID
HAVING (count(*) = ?)
EOF
    is_deeply($stmt->{bind}, ['2'], 'right bind values');

    my $subquery = Blog->driver->prepare_statement('Blog', {}, {});
    $stmt->add_select($subquery, 'SUB');
    $stmt->add_having(SUB => 3);
    is sql_normalize($stmt->as_sql), sql_normalize(<<'EOF');
SELECT
    ENTRY.ID, ENTRY.BLOG_ID, ENTRY.TITLE, ENTRY.TEXT, count(*) COUNT,
    (SELECT BLOG.ID, BLOG.PARENT_ID, BLOG.NAME FROM BLOG) AS SUB
FROM ENTRY
GROUP BY BLOG_ID
HAVING (count(*) = ?) AND (SUB = ?)
EOF
    is_deeply($stmt->{bind}, ['2', '3'], 'right bind values');
};

subtest 'subquery in from clause' => sub {

    subtest 'blogs that has entries with specific text' => sub {
        my $subquery = Entry->driver->prepare_statement(
            'Entry',
            { TEXT => 'second' }, { fetchonly => ['ID', 'BLOG_ID', 'TEXT'] });
        $subquery->as('SUB');
        my $stmt = Blog->driver->prepare_statement(
            'Blog', [
                { 'BLOG.ID'  => \'= SUB.BLOG_ID' },
                { 'BLOG.ID'  => [$blog1->ID, $blog2->ID] },    # FIXME: table prefix should be added automatically (MTC-30879)
            ],
            {});
        push @{ $stmt->from }, $subquery;

        my $expected = sql_normalize(<<'EOF');
SELECT
    BLOG.ID,
    BLOG.PARENT_ID,
    BLOG.NAME
FROM BLOG,
    (
        SELECT ENTRY.ID, ENTRY.BLOG_ID, ENTRY.TEXT
        FROM ENTRY
        WHERE (ENTRY.TEXT = ?)
    ) AS SUB
WHERE ((BLOG.ID = sub.BLOG_ID)) AND ((BLOG.ID IN (?,?)))
EOF

        is sql_normalize($stmt->as_sql), sql_normalize($expected), 'right sql';
        is_deeply($stmt->{bind}, ['second', $blog1->ID, $blog2->ID], 'right bind values');
        my @res = Blog->driver->search('Blog', $stmt);
        is scalar(@res),                             2;
        is scalar(keys %{ $res[0]{column_values} }), 3;
        is($res[0]{column_values}{ID}, $blog1->ID);
    };

    subtest 'select list includes sub query result' => sub {
        my $subquery = Entry->driver->prepare_statement(
            'Entry',
            { TEXT => 'second' }, { fetchonly => ['ID', 'BLOG_ID'] });
        # $subquery->add_select('max(ID)', 'max_entry_id');
        $subquery->as('SUB');
        my $stmt = Blog->driver->prepare_statement(
            'Blog', [
                { 'BLOG.ID' => \'= SUB.BLOG_ID' },            # FIXME: table prefix should be added automatically (MTC-30879)
                { 'BLOG.ID' => [$blog1->ID, $blog2->ID] },    # FIXME: table prefix should be added automatically (MTC-30879)
            ],
            {});
        push @{ $stmt->from }, $subquery;
        $stmt->add_select('SUB.ID', 'ENTRY_ID');

        my $expected = sql_normalize(<<'EOF');
SELECT
    BLOG.ID,
    BLOG.PARENT_ID,
    BLOG.NAME,
    SUB.ID ENTRY_ID
FROM BLOG,
    (
        SELECT ENTRY.ID, ENTRY.BLOG_ID
        FROM ENTRY
        WHERE (ENTRY.TEXT = ?)
    ) AS SUB
WHERE ((BLOG.ID = SUB.BLOG_ID)) AND ((BLOG.ID IN (?,?)))
EOF

        is sql_normalize($stmt->as_sql), sql_normalize($expected), 'right sql';
        is_deeply($stmt->{bind}, ['second', $blog1->ID, $blog2->ID], 'right bind values');
        my @res = Blog->driver->search('Blog', $stmt);
        is scalar(@res),                             2;
        is scalar(keys %{ $res[0]{column_values} }), 4;
        is($res[0]{column_values}{ENTRY_ID}, $entry12->ID);
        is($res[1]{column_values}{ENTRY_ID}, $entry22->ID);
    };
};

subtest 'subquery in where clause' => sub {

    subtest 'entries that belongs to subquery blogs' => sub {
        my $stmt = Entry->driver->prepare_statement(
            'Entry',
            ordered_hashref(
                TEXT    => 'first',
                BLOG_ID => {
                    op    => 'IN',
                    value => Blog->driver->prepare_statement(
                        'Blog',
                        { NAME      => { op => 'LIKE', value => 'blog1', escape => '!' } },
                        { fetchonly => ['ID'] }
                    ),
                }
            ),
            { limit => 4 });

        my $expected = sql_normalize(<<'EOF');
SELECT 
    ENTRY.ID, ENTRY.BLOG_ID, ENTRY.TITLE, ENTRY.TEXT
FROM
    ENTRY
WHERE
    (ENTRY.TEXT = ?)
    AND
    (ENTRY.BLOG_ID IN (SELECT BLOG.ID FROM BLOG WHERE (BLOG.NAME LIKE ? ESCAPE '!')))
LIMIT 4
EOF
        is sql_normalize($stmt->as_sql), sql_normalize($expected), 'right sql';
        is_deeply($stmt->{bind}, ['first', 'blog1'], 'right bind values');
        my @res = Blog->driver->search('Blog', $stmt);
        is scalar(@res),                             1;
        is scalar(keys %{ $res[0]{column_values} }), 4;
        is($res[0]{column_values}{ID}, $blog1->ID);
    };

    subtest 'subquery surrounded by other placeholders' => sub {
        my $stmt = Entry->driver->prepare_statement(
            'Entry',
            [[
                    { TEXT => 'first' },
                    '-or',
                    {
                        BLOG_ID => {
                            op    => 'IN',
                            value => Blog->driver->prepare_statement(
                                'Blog', [
                                    { NAME => { op => 'LIKE', value => 'blog!%', escape => '!' } },
                                    { NAME => { op => 'LIKE', value => '!%2',    escape => '!' } },
                                ],
                                { fetchonly => ['ID'] }) }
                    },
                    '-or',
                    { TEXT => 'second' },
                ],
                { ID => [$entry11->ID, $entry12->ID] },
            ],
            { limit => 4 });

        my $expected = sql_normalize(<<'EOF');
SELECT
    ENTRY.ID, ENTRY.BLOG_ID, ENTRY.TITLE, ENTRY.TEXT
FROM
    ENTRY
WHERE
    (
        ((TEXT = ?))
        OR
        ((BLOG_ID IN (
            SELECT BLOG.ID
            FROM BLOG
            WHERE ((NAME LIKE ? ESCAPE '!')) AND ((NAME LIKE ? ESCAPE '!'))
        )))
        OR
        ((TEXT = ?))
    ) AND (
        (ID IN (?,?))
    )
LIMIT 4
EOF
        is sql_normalize($stmt->as_sql), sql_normalize($expected), 'right sql';
        is_deeply($stmt->{bind}, ['first', 'blog!%', '!%2', 'second', $blog1->ID, $blog2->ID], 'right bind values');
        my @res = Blog->driver->search('Blog', $stmt);
        is scalar(@res),                             2;
        is scalar(keys %{ $res[0]{column_values} }), 4;
        is($res[0]{column_values}{ID}, $blog1->ID);
        is($res[1]{column_values}{ID}, $blog2->ID);
    };
};

subtest 'subquery in multiple clauses' => sub {
    my $sub1 = Entry->driver->prepare_statement(
        'Entry',
        ordered_hashref(BLOG_ID => \'= BLOG.ID', ID => { op => '<', value => 99 }), { fetchonly => ['ID'] });
    $sub1->select(['max(ID)']);
    my $sub2 = Entry->driver->prepare_statement('Entry', { TEXT => 'second' }, { fetchonly => ['ID'] });
    my $sub3 = Entry->driver->prepare_statement('Entry', { TEXT => 'second' }, { fetchonly => ['BLOG_ID'] });
    $sub1->as('SUB1');
    $sub2->as('SUB2');
    $sub3->as('SUB3');    # this will be ommitted in where clause
    my $stmt = Blog->driver->prepare_statement(
        'Blog', { ID => { op => 'IN', value => $sub3 } },
        { sort => [{ column => 'BLOG.ID' }, { column => 'SUB1' }] });
    $stmt->add_select($sub1);
    push @{ $stmt->from }, $sub2;

    my $expected = sql_normalize(<<'EOF');
SELECT
    BLOG.ID,
    BLOG.PARENT_ID,
    BLOG.NAME,
    (SELECT max(ID) FROM ENTRY WHERE (ENTRY.BLOG_ID = BLOG.ID) AND (ENTRY.ID < ?)) AS SUB1
FROM 
    BLOG,
    (SELECT ENTRY.ID FROM ENTRY WHERE (ENTRY.TEXT = ?)) AS SUB2
WHERE
    (BLOG.ID IN (SELECT ENTRY.BLOG_ID FROM ENTRY WHERE (ENTRY.TEXT = ?)))
ORDER BY BLOG.ID ASC, SUB1 ASC
EOF
    is sql_normalize($stmt->as_sql), sql_normalize($expected), 'right sql';
    is_deeply($stmt->{bind}, ['99', 'second', 'second'], 'right bind values');
    my @res = Blog->driver->search('Blog', $stmt);
    is scalar(@res), 4;
    is($res[0]{column_values}{ID},   $blog1->ID);
    is($res[0]{column_values}{SUB1}, $entry12->ID);
    is($res[1]{column_values}{ID},   $blog1->ID);
    is($res[1]{column_values}{SUB1}, $entry12->ID);
    is($res[2]{column_values}{ID},   $blog2->ID);
    is($res[2]{column_values}{SUB1}, $entry22->ID);
    is($res[3]{column_values}{ID},   $blog2->ID);
    is($res[3]{column_values}{SUB1}, $entry22->ID);
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

END {
    disconnect_all(qw/Blog Entry/);
    teardown_dbs(qw( global ));
}

done_testing;
