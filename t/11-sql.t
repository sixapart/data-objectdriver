# $Id$

use strict;

use lib 't/lib';
use Data::ObjectDriver::SQL;
use Test::More tests => 111;
use DodTestUtil;

BEGIN { DodTestUtil->check_driver }

setup_dbs({
    global => [ qw( wines ) ],
});

my $stmt = ns();
ok($stmt, 'Created SQL object');

## Testing FROM
$stmt->from([ 'foo' ]);
is($stmt->as_sql, "FROM foo\n");

$stmt->from([ 'foo', 'bar' ]);
is($stmt->as_sql, "FROM foo, bar\n");

## Testing JOINs
$stmt->from([]);
$stmt->joins([]);
$stmt->add_join(foo => { type => 'inner', table => 'baz',
                         condition => 'foo.baz_id = baz.baz_id' });
is($stmt->as_sql, "FROM foo INNER JOIN baz ON foo.baz_id = baz.baz_id\n");

$stmt->from([ 'bar' ]);
is($stmt->as_sql, "FROM foo INNER JOIN baz ON foo.baz_id = baz.baz_id, bar\n");

$stmt->from([]);
$stmt->joins([]);
$stmt->add_join(foo => [
        { type => 'inner', table => 'baz b1',
          condition => 'foo.baz_id = b1.baz_id AND b1.quux_id = 1' },
        { type => 'left', table => 'baz b2',
          condition => 'foo.baz_id = b2.baz_id AND b2.quux_id = 2' },
    ]);
is $stmt->as_sql, "FROM foo INNER JOIN baz b1 ON foo.baz_id = b1.baz_id AND b1.quux_id = 1 LEFT JOIN baz b2 ON foo.baz_id = b2.baz_id AND b2.quux_id = 2\n";

# test case for bug found where add_join is called twice
$stmt->joins([]);
$stmt->add_join(foo => [
        { type => 'inner', table => 'baz b1',
          condition => 'foo.baz_id = b1.baz_id AND b1.quux_id = 1' },
]);
$stmt->add_join(foo => [
        { type => 'left', table => 'baz b2',
          condition => 'foo.baz_id = b2.baz_id AND b2.quux_id = 2' },
    ]);
is $stmt->as_sql, "FROM foo INNER JOIN baz b1 ON foo.baz_id = b1.baz_id AND b1.quux_id = 1 LEFT JOIN baz b2 ON foo.baz_id = b2.baz_id AND b2.quux_id = 2\n";

# test case adding another table onto the whole mess
$stmt->add_join(quux => [
        { type => 'inner', table => 'foo f1',
          condition => 'f1.quux_id = quux.q_id'}
    ]);

is $stmt->as_sql, "FROM foo INNER JOIN baz b1 ON foo.baz_id = b1.baz_id AND b1.quux_id = 1 LEFT JOIN baz b2 ON foo.baz_id = b2.baz_id AND b2.quux_id = 2 INNER JOIN foo f1 ON f1.quux_id = quux.q_id\n";

# test case for bug found where add_join is called for a table included in the "from".
$stmt->from([ 'foo', 'bar' ]);
$stmt->joins([]);
$stmt->add_join(foo => { type => 'inner', table => 'bar',
                         condition => 'foo.bar_id = bar.bar_id' });
is($stmt->as_sql, "FROM foo INNER JOIN bar ON foo.bar_id = bar.bar_id\n");

## Testing GROUP BY
$stmt = ns();
$stmt->from([ 'foo' ]);
$stmt->group({ column => 'baz' });
is($stmt->as_sql, "FROM foo\nGROUP BY baz\n", 'single bare group by');

$stmt = ns();
$stmt->from([ 'foo' ]);
$stmt->group({ column => 'baz', desc => 'DESC' });
is($stmt->as_sql, "FROM foo\nGROUP BY baz DESC\n", 'single group by with desc');

$stmt = ns();
$stmt->from([ 'foo' ]);
$stmt->group([ { column => 'baz' }, { column => 'quux' }, ]);
is($stmt->as_sql, "FROM foo\nGROUP BY baz, quux\n", 'multiple group by');

$stmt = ns();
$stmt->from([ 'foo' ]);
$stmt->group([ { column => 'baz',  desc => 'DESC' },
               { column => 'quux', desc => 'DESC' }, ]);
is($stmt->as_sql, "FROM foo\nGROUP BY baz DESC, quux DESC\n", 'multiple group by with desc');

## Testing ORDER BY
$stmt = ns();
$stmt->from([ 'foo' ]);
$stmt->order({ column => 'baz', desc => 'DESC' });
is($stmt->as_sql, "FROM foo\nORDER BY baz DESC\n", 'single order by');

$stmt = ns();
$stmt->from([ 'foo' ]);
$stmt->order([ { column => 'baz',  desc => 'DESC' },
               { column => 'quux', desc => 'ASC'  }, ]);
is($stmt->as_sql, "FROM foo\nORDER BY baz DESC, quux ASC\n", 'multiple order by');

## Testing GROUP BY plus ORDER BY
$stmt = ns();
$stmt->from([ 'foo' ]);
$stmt->group({ column => 'quux' });
$stmt->order({ column => 'baz', desc => 'DESC' });
is($stmt->as_sql, "FROM foo\nGROUP BY quux\nORDER BY baz DESC\n", 'group by with order by');

## Testing LIMIT and OFFSET
$stmt = ns();
$stmt->from([ 'foo' ]);
$stmt->limit(5);
is($stmt->as_sql, "FROM foo\nLIMIT 5\n");
$stmt->offset(10);
is($stmt->as_sql, "FROM foo\nLIMIT 5 OFFSET 10\n");
$stmt->limit("  15g");  ## Non-numerics should cause an error
{
    my $sql = eval { $stmt->as_sql };
    like($@, qr/Non-numerics/, "bogus limit causes as_sql assertion");
}

## Testing WHERE
$stmt = ns(); $stmt->add_where(foo => 'bar');
is($stmt->as_sql_where, "WHERE (foo = ?)\n");
is(scalar @{ $stmt->bind }, 1);
is($stmt->bind->[0], 'bar');

$stmt = ns(); $stmt->add_where(foo => [ 'bar', 'baz' ]);
is($stmt->as_sql_where, "WHERE (foo IN (?,?))\n");
is(scalar @{ $stmt->bind }, 2);
is($stmt->bind->[0], 'bar');
is($stmt->bind->[1], 'baz');

$stmt = ns(); $stmt->add_where(foo => { op => 'IN', value => ['bar'] });
is($stmt->as_sql_where, "WHERE (foo IN (?))\n");
is(scalar @{ $stmt->bind }, 1);
is($stmt->bind->[0], 'bar');

$stmt = ns(); $stmt->add_where(foo => { op => 'NOT IN', value => ['bar'] });
is($stmt->as_sql_where, "WHERE (foo NOT IN (?))\n");
is(scalar @{ $stmt->bind }, 1);
is($stmt->bind->[0], 'bar');

$stmt = ns(); $stmt->add_where(foo => { op => 'BETWEEN', value => ['bar', 'baz'] });
is($stmt->as_sql_where, "WHERE (foo BETWEEN ? AND ?)\n");
is(scalar @{ $stmt->bind }, 2);
is($stmt->bind->[0], 'bar');
is($stmt->bind->[1], 'baz');

$stmt = ns(); $stmt->add_where(foo => { op => 'LIKE', value => 'bar%' });
is($stmt->as_sql_where, "WHERE (foo LIKE ?)\n");
is(scalar @{ $stmt->bind }, 1);
is($stmt->bind->[0], 'bar%');

$stmt = ns(); $stmt->add_where(foo => { op => '!=', value => 'bar' });
is($stmt->as_sql_where, "WHERE (foo != ?)\n");
is(scalar @{ $stmt->bind }, 1);
is($stmt->bind->[0], 'bar');

$stmt = ns(); $stmt->add_where(foo => { column => 'bar', op => '!=', value => 'bar' });
is($stmt->as_sql_where, "WHERE (bar != ?)\n");
is(scalar @{ $stmt->bind }, 1);
is($stmt->bind->[0], 'bar');

$stmt = ns(); $stmt->add_where(foo => \'IS NOT NULL');
is($stmt->as_sql_where, "WHERE (foo IS NOT NULL)\n");
is(scalar @{ $stmt->bind }, 0);

$stmt = ns();
$stmt->add_where(foo => 'bar');
$stmt->add_where(baz => 'quux');
is($stmt->as_sql_where, "WHERE (foo = ?) AND (baz = ?)\n");
is(scalar @{ $stmt->bind }, 2);
is($stmt->bind->[0], 'bar');
is($stmt->bind->[1], 'quux');

$stmt = ns();
$stmt->add_where(foo => [ { op => '>', value => 'bar' },
                          { op => '<', value => 'baz' } ]);
is($stmt->as_sql_where, "WHERE ((foo > ?) OR (foo < ?))\n");
is(scalar @{ $stmt->bind }, 2);
is($stmt->bind->[0], 'bar');
is($stmt->bind->[1], 'baz');

$stmt = ns();
$stmt->add_where(foo => [ -and => { op => '>', value => 'bar' },
                                  { op => '<', value => 'baz' } ]);
is($stmt->as_sql_where, "WHERE ((foo > ?) AND (foo < ?))\n");
is(scalar @{ $stmt->bind }, 2);
is($stmt->bind->[0], 'bar');
is($stmt->bind->[1], 'baz');

$stmt = ns();
$stmt->add_where(foo => [ -and => 'foo', 'bar', 'baz']);
is($stmt->as_sql_where, "WHERE ((foo = ?) AND (foo = ?) AND (foo = ?))\n");
is(scalar @{ $stmt->bind }, 3);
is($stmt->bind->[0], 'foo');
is($stmt->bind->[1], 'bar');
is($stmt->bind->[2], 'baz');

$stmt = ns();
$stmt->add_where(foo => \['IN (SELECT foo FROM bar WHERE t=?)', 'foo']);
is($stmt->as_sql_where, "WHERE (foo IN (SELECT foo FROM bar WHERE t=?))\n");
is(scalar @{ $stmt->bind }, 1);
is($stmt->bind->[0], 'foo');

$stmt = ns();
$stmt->add_where(foo => { op => 'IN', value => \['(SELECT foo FROM bar WHERE t=?)', 'foo']});
is($stmt->as_sql_where, "WHERE (foo IN ((SELECT foo FROM bar WHERE t=?)))\n");
is(scalar @{ $stmt->bind }, 1);
is($stmt->bind->[0], 'foo');

$stmt = ns();
$stmt->add_where(foo => { op => 'IN', value => \'(SELECT foo FROM bar)'});
is($stmt->as_sql_where, "WHERE (foo IN (SELECT foo FROM bar))\n");
is(scalar @{ $stmt->bind }, 0);

$stmt = ns();
$stmt->add_where(foo => undef);
is($stmt->as_sql_where, "WHERE (foo IS NULL)\n");
is(scalar @{ $stmt->bind }, 0);

## avoid syntax error
$stmt = ns();
$stmt->add_where(foo => []);
is($stmt->as_sql_where, "WHERE (0 = 1)\n"); # foo IN ()
is(scalar @{ $stmt->bind }, 0);

$stmt = ns();
$stmt->add_complex_where([]);
is($stmt->as_sql_where, "");  # no WHERE without expression
is(scalar @{ $stmt->bind }, 0);

$stmt = ns();
$stmt->add_complex_where([[]]);
is($stmt->as_sql_where, "");  # no WHERE without expression
is(scalar @{ $stmt->bind }, 0);

$stmt = ns();
$stmt->add_complex_where([{}]);
is($stmt->as_sql_where, "");  # no WHERE without expression
is(scalar @{ $stmt->bind }, 0);

$stmt = ns();
$stmt->add_complex_where([{id => 1}, {}]);
is($stmt->as_sql_where, "WHERE ((id = ?))\n");  # no empty expression
is(scalar @{ $stmt->bind }, 1);

$stmt = ns();
$stmt->add_complex_where([{id => 1}, []]);
is($stmt->as_sql_where, "WHERE ((id = ?))\n");  # no empty expression
is(scalar @{ $stmt->bind }, 1);

## regression bug. modified parameters
my %terms = ( foo => [-and => 'foo', 'bar', 'baz']);
$stmt = ns();
$stmt->add_where(%terms);
is($stmt->as_sql_where, "WHERE ((foo = ?) AND (foo = ?) AND (foo = ?))\n");
$stmt->add_where(%terms);
is($stmt->as_sql_where, "WHERE ((foo = ?) AND (foo = ?) AND (foo = ?)) AND ((foo = ?) AND (foo = ?) AND (foo = ?))\n");

## as_escape
$stmt = ns();
$stmt->add_where(foo => { op => 'LIKE', value => '100%', escape => '\\' });
is($stmt->as_sql_where, "WHERE (foo LIKE ? ESCAPE '\\')\n");
is($stmt->bind->[0],    '100%');                               # escape doesn't automatically escape the value
$stmt = ns();
$stmt->add_where(foo => { op => 'LIKE', value => '100\\%', escape => '\\' });
is($stmt->as_sql_where, "WHERE (foo LIKE ? ESCAPE '\\')\n");
is($stmt->bind->[0],    '100\\%');
$stmt = ns();
$stmt->add_where(foo => { op => 'LIKE', value => '100%', escape => '!' });
is($stmt->as_sql_where, "WHERE (foo LIKE ? ESCAPE '!')\n");
$stmt = ns();
$stmt->add_where(foo => { op => 'LIKE', value => '100%', escape => "''" });
is($stmt->as_sql_where, "WHERE (foo LIKE ? ESCAPE '''')\n");
$stmt = ns();
$stmt->add_where(foo => { op => 'LIKE', value => '100%', escape => "\\'" });
is($stmt->as_sql_where, "WHERE (foo LIKE ? ESCAPE '\\'')\n");
$stmt = ns();
eval { $stmt->add_where(foo => { op => 'LIKE', value => '_', escape => "!!!" }); };
like($@, qr/length/, 'right error');

$stmt = ns();
$stmt->add_select(foo => 'foo');
$stmt->add_select('bar');
$stmt->from([ qw( baz ) ]);
is($stmt->as_sql, "SELECT foo, bar\nFROM baz\n");

subtest 'SQL functions' => sub {
    $stmt = ns();
    $stmt->add_select('f.foo' => 'foo');
    $stmt->add_select('COUNT(*)' => 'count');
    $stmt->from([ qw( baz ) ]);
    is($stmt->as_sql, "SELECT f.foo, COUNT(*) count\nFROM baz\n");
    my $map = $stmt->select_map;
    is(scalar(keys %$map), 2);
    is_deeply($map, {'f.foo' => 'foo', 'COUNT(*)' => 'count'}, 'right map');

    $stmt = ns();
    $stmt->add_select('count(foo)');
    $stmt->add_select('count(bar)');
    $stmt->from([qw( baz )]);
    is($stmt->as_sql, "SELECT count(foo), count(bar)\nFROM baz\n");
    my $map = $stmt->select_map;
    is(scalar(keys %$map), 2);
    is_deeply($map, {'count(foo)' => 'count(foo)', 'count(bar)' => 'count(bar)'}, 'right map');

    $stmt = ns();
    $stmt->add_select('count(foo)', 'count1');
    $stmt->add_select('count(bar)', 'count2');
    $stmt->from([qw( baz )]);
    is($stmt->as_sql, "SELECT count(foo) count1, count(bar) count2\nFROM baz\n");
    my $map = $stmt->select_map;
    is(scalar(keys %$map), 2);
    is_deeply($map, {'count(foo)' => 'count1', 'count(bar)' => 'count2'}, 'right map');
};

# HAVING
$stmt = ns();
$stmt->add_select(foo => 'foo');
$stmt->add_select('COUNT(*)' => 'count');
$stmt->from([ qw(baz) ]);
$stmt->add_where(foo => 1);
$stmt->group({ column => 'baz' });
$stmt->order({ column => 'foo', desc => 'DESC' });
$stmt->limit(2);
$stmt->add_having(count => 2);

is($stmt->as_sql, <<SQL);
SELECT foo, COUNT(*) count
FROM baz
WHERE (foo = ?)
GROUP BY baz
HAVING (COUNT(*) = ?)
ORDER BY foo DESC
LIMIT 2
SQL

# DISTINCT
$stmt = ns();
$stmt->add_select(foo => 'foo');
$stmt->from([ qw(baz) ]);
is($stmt->as_sql, "SELECT foo\nFROM baz\n", "DISTINCT is absent by default");
$stmt->distinct(1);
is($stmt->as_sql, "SELECT DISTINCT foo\nFROM baz\n", "we can turn on DISTINCT");

# index hint
$stmt = ns();
$stmt->add_select(foo => 'foo');
$stmt->from([ qw(baz) ]);
is($stmt->as_sql, "SELECT foo\nFROM baz\n", "index hint is absent by default");
$stmt->add_index_hint('baz' => { type => 'USE', list => ['index_hint']});
is($stmt->as_sql, "SELECT foo\nFROM baz USE INDEX (index_hint)\n", "we can turn on USE INDEX");

# index hint with joins
$stmt->joins([]);
$stmt->from([]);
$stmt->add_join(baz => { type => 'inner', table => 'baz',
                         condition => 'baz.baz_id = foo.baz_id' });
is($stmt->as_sql, "SELECT foo\nFROM baz USE INDEX (index_hint) INNER JOIN baz ON baz.baz_id = foo.baz_id\n", 'USE INDEX with JOIN');
$stmt->from([]);
$stmt->joins([]);
$stmt->add_join(baz => [
        { type => 'inner', table => 'baz b1',
          condition => 'baz.baz_id = b1.baz_id AND b1.quux_id = 1' },
        { type => 'left', table => 'baz b2',
          condition => 'baz.baz_id = b2.baz_id AND b2.quux_id = 2' },
    ]);
is($stmt->as_sql, "SELECT foo\nFROM baz USE INDEX (index_hint) INNER JOIN baz b1 ON baz.baz_id = b1.baz_id AND b1.quux_id = 1 LEFT JOIN baz b2 ON baz.baz_id = b2.baz_id AND b2.quux_id = 2\n", 'USE INDEX with JOINs');

$stmt = ns();
$stmt->add_select(foo => 'foo');
$stmt->from([ qw(baz) ]);
$stmt->comment("mycomment");
is($stmt->as_sql, "SELECT foo\nFROM baz\n-- mycomment");

$stmt->comment("\nbad\n\nmycomment");
is($stmt->as_sql, "SELECT foo\nFROM baz\n-- bad", "correctly untainted");

$stmt->comment("G\\G");
is($stmt->as_sql, "SELECT foo\nFROM baz\n-- G", "correctly untainted");

## Testing complex WHERE
$stmt = ns();
$stmt->add_complex_where([
    { foo => 'foo_value' },
    { bar => 'bar_value' },
]);
is($stmt->as_sql_where, "WHERE ((foo = ?)) AND ((bar = ?))\n");

$stmt = ns();
my @terms = (
    { foo => 'foo_value' },
    {
        bar => [
            { op => 'LIKE', value => 'bar1%' },
            { op => 'LIKE', value => 'bar2%' },
        ],
        baz => 'baz_value',
    }
);
$stmt->add_complex_where(\@terms);
is(
    $stmt->as_sql_where,
    (keys(%{$terms[1]}))[0] eq 'bar'
        ?  "WHERE ((foo = ?)) AND (((bar LIKE ?) OR (bar LIKE ?)) AND (baz = ?))\n"
        :  "WHERE ((foo = ?)) AND ((baz = ?) AND ((bar LIKE ?) OR (bar LIKE ?)))\n"
);

subtest 'quote can be used based on given dbh' => sub {
    use Wine;
    $stmt = ns({dbh => Wine->driver->rw_handle});
    $stmt->add_select(foo => 'bar');
    @{$stmt->from} = ('baz');
    my $quoted = Wine->driver->dbh->quote_identifier('bar');
    is sql_normalize($stmt->as_sql), sql_normalize(<<"EOF"), 'right sql';
SELECT foo $quoted FROM baz
EOF
};

sub ns { Data::ObjectDriver::SQL->new(@_) }

sub sql_normalize {
    my $sql = shift;
    $sql =~ s{\s+}{ }g;
    $sql =~ s{\( }{(}g;
    $sql =~ s{ \)}{)}g;
    $sql =~ s{([\(\)]) ([\(\)])}{$1$2}g;
    $sql;
}

END {
    disconnect_all(qw/Wine/);
    teardown_dbs(qw( global ));
}
