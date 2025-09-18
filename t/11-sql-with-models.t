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
    global => [qw( blog entry )],
});

my $blog1 = Blog->new(name => 'blog1');
$blog1->save;
my $blog2 = Blog->new(parent_id => $blog1->id, name => 'blog2');
$blog2->save;
my $entry11 = Entry->new(blog_id => $blog1->id, title => 'title11', text => 'first');
$entry11->save;
my $entry12 = Entry->new(blog_id => $blog1->id, title => 'title12', text => 'second');
$entry12->save;
my $entry21 = Entry->new(blog_id => $blog2->id, title => 'title21', text => 'first');
$entry21->save;
my $entry22 = Entry->new(blog_id => $blog2->id, title => 'title22', text => 'second');
$entry22->save;

subtest 'as_subquery' => sub {
    my $stmt = Blog->driver->prepare_statement('Blog', { name => 'foo' }, { fetchonly => ['id'] });

    is(sql_normalize($stmt->as_subquery), sql_normalize(<<'EOF'), 'right sql');
(SELECT blog.id FROM blog WHERE (blog.name = ?))
EOF
    is_deeply($stmt->{bind}, ['foo'], 'right bind values');

    $stmt->as('mysubquery');

    is(sql_normalize($stmt->as_subquery), sql_normalize(<<'EOF'), 'right sql');
(SELECT blog.id FROM blog WHERE (blog.name = ?)) AS mysubquery
EOF
};

subtest 'do not aggregate bind twice' => sub {

    my $stmt     = Blog->driver->prepare_statement('Blog', [{ name => $blog1->name }], {});
    my $subquery = Entry->driver->prepare_statement(
        'Entry',
        ordered_hashref(blog_id => \'= blog.id', text => 'second'),
        { fetchonly => ['id'], limit => 1 });
    $subquery->as('sub');
    $stmt->add_select($subquery);
    $stmt->as_sql;
    is scalar(@{ $stmt->bind }), 2;
    $stmt->as_sql;
    is scalar(@{ $stmt->bind }), 2;
};

subtest 'subquery in select clause' => sub {

    subtest 'fetch blogs and include a entry with specific text if any' => sub {
        my $stmt     = Blog->driver->prepare_statement('Blog', [{ name => $blog1->name }], {});
        my $subquery = Entry->driver->prepare_statement(
            'Entry',
            ordered_hashref(blog_id => \'= blog.id', text => 'second'),
            { fetchonly => ['id'], limit => 1 });
        $subquery->as('sub_alias');
        $stmt->add_select($subquery);

        my $expected = sql_normalize(<<'EOF');
SELECT
    blog.id,
    blog.parent_id,
    blog.name,
    (
        SELECT entry.id
        FROM entry
        WHERE (entry.blog_id = blog.id) AND (entry.text = ?)
        LIMIT 1
    ) AS sub_alias
FROM blog
WHERE ((name = ?))
EOF

        is sql_normalize($stmt->as_sql), sql_normalize($expected), 'right sql';
        is_deeply($stmt->{bind}, ['second', $blog1->name], 'right bind values');
        my @res = search_by_prepared_statement('Blog', $stmt);
        is scalar(@res),                             1;
        is scalar(keys %{ $res[0]{column_values} }), 4;
        is($res[0]{column_values}{id},        $blog1->id);
        is($res[0]{column_values}{sub_alias}, $entry12->id);
    };

    subtest 'error occurs without alias' => sub {
        my $stmt     = Blog->driver->prepare_statement('Blog', [], {});
        my $subquery = Entry->driver->prepare_statement(
            'Entry',
            [{ blog_id => \'= blog.id' }], { fetchonly => ['id'], limit => 1 });
        eval { $stmt->add_select($subquery) };
        like $@, qr/requires an alias/;
    };
};

subtest 'subquery in from clause' => sub {

    subtest 'blogs that has entries with specific text' => sub {
        my $subquery = Entry->driver->prepare_statement(
            'Entry',
            { text => 'second' }, { fetchonly => ['id', 'blog_id', 'text'] });
        $subquery->as('sub');
        my $stmt = Blog->driver->prepare_statement(
            'Blog', [
                { 'blog.id'  => \'= sub.blog_id' },
                { 'blog.id'  => [$blog1->id, $blog2->id] },    # FIXME: table prefix should be added automatically (MTC-30879)
                { 'sub.text' => 'second' },
            ],
            {});
        push @{ $stmt->from }, $subquery;

        my $expected = sql_normalize(<<'EOF');
SELECT
    blog.id,
    blog.parent_id,
    blog.name
FROM blog,
    (
        SELECT entry.id, entry.blog_id, entry.text
        FROM entry
        WHERE (entry.text = ?)
    ) AS sub
WHERE ((blog.id = sub.blog_id)) AND ((blog.id IN (?,?))) AND ((sub.text = ?))
EOF

        is sql_normalize($stmt->as_sql), sql_normalize($expected), 'right sql';
        is_deeply($stmt->{bind}, ['second', $blog1->id, $blog2->id, 'second'], 'right bind values');
        my @res = search_by_prepared_statement('Blog', $stmt);
        is scalar(@res),                             2;
        is scalar(keys %{ $res[0]{column_values} }), 3;
        is($res[0]{column_values}{id}, $blog1->id);
    };

    subtest 'select list includes sub query result' => sub {
        my $subquery = Entry->driver->prepare_statement(
            'Entry',
            { text => 'second' }, { fetchonly => ['id', 'blog_id'] });
        # $subquery->add_select('max(id)', 'max_entry_id');
        $subquery->as('sub');
        my $stmt = Blog->driver->prepare_statement(
            'Blog', [
                { 'blog.id' => \'= sub.blog_id' },            # FIXME: table prefix should be added automatically (MTC-30879)
                { 'blog.id' => [$blog1->id, $blog2->id] },    # FIXME: table prefix should be added automatically (MTC-30879)
            ],
            {});
        push @{ $stmt->from }, $subquery;
        $stmt->add_select('sub.id', 'entry_id');

        my $expected = sql_normalize(<<'EOF');
SELECT
    blog.id,
    blog.parent_id,
    blog.name,
    sub.id entry_id
FROM blog,
    (
        SELECT entry.id, entry.blog_id
        FROM entry
        WHERE (entry.text = ?)
    ) AS sub
WHERE ((blog.id = sub.blog_id)) AND ((blog.id IN (?,?)))
EOF

        is sql_normalize($stmt->as_sql), sql_normalize($expected), 'right sql';
        is_deeply($stmt->{bind}, ['second', $blog1->id, $blog2->id], 'right bind values');
        my @res = search_by_prepared_statement('Blog', $stmt);
        is scalar(@res),                             2;
        is scalar(keys %{ $res[0]{column_values} }), 4;
        is($res[0]{column_values}{entry_id}, $entry12->id);
        is($res[1]{column_values}{entry_id}, $entry22->id);
    };
};

subtest 'subquery in where clause' => sub {

    subtest 'entries that belongs to subquery blogs' => sub {
        my $stmt = Entry->driver->prepare_statement(
            'Entry',
            ordered_hashref(
                text    => 'first',
                blog_id => {
                    op    => 'IN',
                    value => Blog->driver->prepare_statement(
                        'Blog',
                        { name      => { op => 'LIKE', value => 'blog1', escape => '!' } },
                        { fetchonly => ['id'] }
                    ),
                }
            ),
            { limit => 4 });

        my $expected = sql_normalize(<<'EOF');
SELECT 
    entry.id, entry.blog_id, entry.title, entry.text
FROM
    entry
WHERE
    (entry.text = ?)
    AND
    (entry.blog_id IN (SELECT blog.id FROM blog WHERE (blog.name LIKE ? ESCAPE '!')))
LIMIT 4
EOF
        is sql_normalize($stmt->as_sql), sql_normalize($expected), 'right sql';
        is_deeply($stmt->{bind}, ['first', 'blog1'], 'right bind values');
        my @res = search_by_prepared_statement('Blog', $stmt);
        is scalar(@res),                             1;
        is scalar(keys %{ $res[0]{column_values} }), 4;
        is($res[0]{column_values}{id}, $blog1->id);
    };

    subtest 'case2' => sub {
        my $stmt = Entry->driver->prepare_statement(
            'Entry',
            [[
                    { text => 'first' },
                    '-or',
                    {
                        blog_id => {
                            op    => 'IN',
                            value => Blog->driver->prepare_statement(
                                'Blog', [
                                    { name => { op => 'LIKE', value => 'blog!%', escape => '!' } },
                                    { name => { op => 'LIKE', value => '!%2',    escape => '!' } },
                                ],
                                { fetchonly => ['id'] }) }
                    },
                    '-or',
                    { text => 'second' },
                ],
                { id => [$entry11->id, $entry12->id] },
            ],
            { limit => 4 });

        my $expected = sql_normalize(<<'EOF');
SELECT
    entry.id, entry.blog_id, entry.title, entry.text
FROM
    entry
WHERE
    (
        ((text = ?))
        OR
        ((blog_id IN (
            SELECT blog.id
            FROM blog
            WHERE ((name LIKE ? ESCAPE '!')) AND ((name LIKE ? ESCAPE '!'))
        )))
        OR
        ((text = ?))
    ) AND (
        (id IN (?,?))
    )
LIMIT 4
EOF
        is sql_normalize($stmt->as_sql), sql_normalize($expected), 'right sql';
        is_deeply($stmt->{bind}, ['first', 'blog!%', '!%2', 'second', $blog1->id, $blog2->id], 'right bind values');
        my @res = search_by_prepared_statement('Blog', $stmt);
        is scalar(@res),                             2;
        is scalar(keys %{ $res[0]{column_values} }), 4;
        is($res[0]{column_values}{id}, $blog1->id);
        is($res[1]{column_values}{id}, $blog2->id);
    };
};

subtest 'subquery in multiple clauses' => sub {
    my $sub1 = Entry->driver->prepare_statement(
        'Entry',
        ordered_hashref(blog_id => \'= blog.id', id => { op => '<', value => 99 }), { fetchonly => ['id'] });
    $sub1->select(['max(id)']);
    my $sub2 = Entry->driver->prepare_statement('Entry', { text => 'second' }, { fetchonly => ['id'] });
    my $sub3 = Entry->driver->prepare_statement('Entry', { text => 'second' }, { fetchonly => ['blog_id'] });
    $sub1->as('sub1');
    $sub2->as('sub2');
    $sub3->as('sub3');    # this will be ommitted in where clause
    my $stmt = Blog->driver->prepare_statement(
        'Blog', { id => { op => 'IN', value => $sub3 } },
        { sort => [{ column => 'blog.id' }, { column => 'sub1' }] });
    $stmt->add_select($sub1);
    push @{ $stmt->from }, $sub2;

    my $expected = sql_normalize(<<'EOF');
SELECT
    blog.id,
    blog.parent_id,
    blog.name,
    (SELECT max(id) FROM entry WHERE (entry.blog_id = blog.id) AND (entry.id < ?)) AS sub1
FROM 
    blog,
    (SELECT entry.id FROM entry WHERE (entry.text = ?)) AS sub2
WHERE
    (blog.id IN (SELECT entry.blog_id FROM entry WHERE (entry.text = ?)))
ORDER BY blog.id ASC, sub1 ASC
EOF
    is sql_normalize($stmt->as_sql), sql_normalize($expected), 'right sql';
    is_deeply($stmt->{bind}, ['99', 'second', 'second'], 'right bind values');
    my @res = search_by_prepared_statement('Blog', $stmt);
    is scalar(@res), 4;
    is($res[0]{column_values}{id},   $blog1->id);
    is($res[0]{column_values}{sub1}, $entry12->id);
    is($res[1]{column_values}{id},   $blog1->id);
    is($res[1]{column_values}{sub1}, $entry12->id);
    is($res[2]{column_values}{id},   $blog2->id);
    is($res[2]{column_values}{sub1}, $entry22->id);
    is($res[3]{column_values}{id},   $blog2->id);
    is($res[3]{column_values}{sub1}, $entry22->id);
};

sub search_by_prepared_statement {
    my ($class, $stmt) = @_;
    my $driver = $class->driver;
    my $rec    = {};
    my $sql    = $stmt->as_sql;
    my @bind;
    my $map = $stmt->select_map;
    for my $col (@{ $stmt->select }) {
        push @bind, \$rec->{ $map->{$col} || $col };
    }

    my $dbh = $driver->r_handle($class->properties->{db});
    $driver->start_query($sql, $stmt->{bind});

    my $sth = $dbh->prepare($sql);
    $sth->execute(@{ $stmt->{bind} });
    $sth->bind_columns(undef, @bind);

    my $iter = sub {
        my $d = $driver;
        unless ($sth->fetch) {
            _close_sth($sth);
            $driver->end_query($sth);
            return;
        }
        return $driver->load_object_from_rec($class, $rec);
    };

    if (wantarray) {
        my @objs = ();
        while (my $obj = $iter->()) {
            push @objs, $obj;
        }
        return @objs;
    } else {
        my $iterator = Data::ObjectDriver::Iterator->new(
            $iter, sub { _close_sth($sth); $driver->end_query($sth) },
        );
        return $iterator;
    }
    return;
}

sub _close_sth {
    my $sth = shift;
    $sth->finish;
    undef $sth;
}

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
