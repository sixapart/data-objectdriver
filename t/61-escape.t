# $Id$

use strict;
use warnings;
use lib 't/lib';
use lib 't/lib/cached';
use Test::More;
use Test::Exception;
use DodTestUtil;

BEGIN {
    DodTestUtil->check_driver;

    unless (eval { require Cache::Memory }) {
        plan skip_all => 'Tests require Cache::Memory';
    }
}

plan tests => 6;

use Foo;

setup_dbs({ global => ['foo'] });

my $foo1 = Foo->new;
$foo1->name('foo');
$foo1->text('100%');
$foo1->save;

my $foo2 = Foo->new;
$foo2->name('bar');
$foo2->text('100_');
$foo2->save;

my $foo3 = Foo->new;
$foo3->name('bar');
$foo3->text('100!');
$foo3->save;

subtest 'escape_char 1' => sub {
    my @got = Foo->search({ text => { op => 'LIKE', value => '100!%', escape => '!' } });
    is scalar(@got),  1,     'right number';
    is $got[0]->name, 'foo', 'right name';
};

subtest 'escape_char 2' => sub {
    my @got = Foo->search({ text => { op => 'LIKE', value => '100#_', escape => '#' } });
    is scalar(@got),  1,     'right number';
    is $got[0]->name, 'bar', 'right name';
};

subtest 'self escape' => sub {
    my @got = Foo->search({ text => { op => 'LIKE', value => '100!!', escape => '!' } });
    is scalar(@got),  1,     'right number';
    is $got[0]->name, 'bar', 'right name';
};

subtest 'use wildcard charactor as escapr_char' => sub {
    plan skip_all => 'MariaDB does not support it' if Foo->driver->dbh->{Driver}->{Name} eq 'MariaDB';
    my @got = Foo->search({ text => { op => 'LIKE', value => '100_%', escape => '_' } });
    is scalar(@got),  1,     'right number';
    is $got[0]->name, 'foo', 'right name';
};

subtest 'use of special characters' => sub {
    subtest 'escape_char single quote' => sub {
        my @got = Foo->search({ text => { op => 'LIKE', value => "100'_", escape => "''" } });
        is scalar(@got),  1,     'right number';
        is $got[0]->name, 'bar', 'right name';
    };

    if (Foo->driver->dbh->{Driver}->{Name} =~ /mysql|mariadb/i) {
        subtest 'escape_char single quote' => sub {
            my @got = Foo->search({ text => { op => 'LIKE', value => "100'_", escape => "\\'" } });
            is scalar(@got),  1,     'right number';
            is $got[0]->name, 'bar', 'right name';
        };

        subtest 'escape_char backslash' => sub {
            my @got = Foo->search({ text => { op => 'LIKE', value => '100\\_', escape => '\\\\' } });
            is scalar(@got),  1,     'right number';
            is $got[0]->name, 'bar', 'right name';
        };
    } else {
        subtest 'escape_char backslash' => sub {
            my @got = Foo->search({ text => { op => 'LIKE', value => '100\\_', escape => '\\' } });
            is scalar(@got),  1,     'right number';
            is $got[0]->name, 'bar', 'right name';
        };
    }
};

subtest 'is safe' => sub {
    eval { Foo->search({ text => { op => 'LIKE', value => '_', escape => q{!');select 'vulnerable'; -- } } }); };
    like $@, qr/escape_char length must be up to two characters/, 'error occurs';
};

END {
    disconnect_all(qw/Foo/);
    teardown_dbs(qw( global ));
}
