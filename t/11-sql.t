# $Id$

use strict;

use Data::ObjectDriver::SQL;
use Test::More tests => 33;

my $stmt = ns();
ok($stmt, 'Created SQL object');

## Testing FROM
$stmt->from([ 'foo' ]);
is($stmt->as_sql, "FROM foo\n");

$stmt->from([ 'foo', 'bar' ]);
is($stmt->as_sql, "FROM foo, bar\n");

$stmt->from([ 'foo' ]);
$stmt->join({ type => 'inner', table => 'baz',
              condition => 'foo.baz_id = baz.baz_id' });
is($stmt->as_sql, "FROM foo INNER JOIN baz ON foo.baz_id = baz.baz_id\n");

$stmt->from([ 'foo', 'bar' ]);
is($stmt->as_sql, "FROM foo INNER JOIN baz ON foo.baz_id = baz.baz_id, bar\n");

## Testing ORDER BY
$stmt = ns();
$stmt->from([ 'foo' ]);
$stmt->order({ column => 'baz', desc => 'DESC' });
is($stmt->as_sql, "FROM foo\nORDER BY baz DESC\n");

## Testing LIMIT and OFFSET
$stmt = ns();
$stmt->from([ 'foo' ]);
$stmt->limit(5);
is($stmt->as_sql, "FROM foo\nLIMIT 5\n");
$stmt->offset(10);
is($stmt->as_sql, "FROM foo\nLIMIT 5 OFFSET 10\n");
$stmt->limit("  15g");  ## Non-numerics should be stripped.
is($stmt->as_sql, "FROM foo\nLIMIT 15 OFFSET 10\n");

## Testing WHERE
$stmt = ns(); $stmt->add_where(foo => 'bar');
is($stmt->as_sql_where, "WHERE (foo = ?)\n");
is(scalar @{ $stmt->bind }, 1);
is($stmt->bind->[0], 'bar');

$stmt = ns(); $stmt->add_where(foo => [ 'bar', 'baz' ]);
is($stmt->as_sql_where, "WHERE (foo = ? OR foo = ?)\n");
is(scalar @{ $stmt->bind }, 2);
is($stmt->bind->[0], 'bar');
is($stmt->bind->[1], 'baz');

$stmt = ns(); $stmt->add_where(foo => { op => '!=', value => 'bar' });
is($stmt->as_sql_where, "WHERE (foo != ?)\n");
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
is($stmt->as_sql_where, "WHERE (foo > ? OR foo < ?)\n");
is(scalar @{ $stmt->bind }, 2);
is($stmt->bind->[0], 'bar');
is($stmt->bind->[1], 'baz');

$stmt = ns();
$stmt->add_where(foo => [ -and => { op => '>', value => 'bar' },
                                  { op => '<', value => 'baz' } ]);
is($stmt->as_sql_where, "WHERE (foo > ? AND foo < ?)\n");
is(scalar @{ $stmt->bind }, 2);
is($stmt->bind->[0], 'bar');
is($stmt->bind->[1], 'baz');

sub ns { Data::ObjectDriver::SQL->new }
