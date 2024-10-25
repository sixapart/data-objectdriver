# $Id$

use strict;
use warnings;
use lib 't/lib';
use lib 't/lib/escape';
use Test::More;
use DodTestUtil;

BEGIN {
    DodTestUtil->check_driver;
}

plan tests => 6;

use Foo;

setup_dbs({ global => ['foo'] });

my $percent = Foo->new;
$percent->name('percent');
$percent->text('100%');
$percent->save;

my $underscore = Foo->new;
$underscore->name('underscore');
$underscore->text('100_');
$underscore->save;

my $exclamation = Foo->new;
$exclamation->name('exclamation');
$exclamation->text('100!');
$exclamation->save;

subtest 'escape_char 1' => sub {
    my @got = Foo->search({ text => { op => 'LIKE', value => '100!%', escape => '!' } });
    is scalar(@got),  1,         'right number';
    is $got[0]->name, 'percent', 'right name';
};

subtest 'escape_char 2' => sub {
    my @got = Foo->search({ text => { op => 'LIKE', value => '100#_', escape => '#' } });
    is scalar(@got),  1,            'right number';
    is $got[0]->name, 'underscore', 'right name';
};

subtest 'self escape' => sub {
    my @got = Foo->search({ text => { op => 'LIKE', value => '100!!', escape => '!' } });
    is scalar(@got),  1,             'right number';
    is $got[0]->name, 'exclamation', 'right name';
};

subtest 'use wildcard charactor as escapr_char' => sub {
    plan skip_all => 'MariaDB does not support it' if Foo->driver->dbh->{Driver}->{Name} eq 'MariaDB';
    plan skip_all => 'SQLite does not support it' if Foo->driver->dbh->{Driver}->{Name} eq 'SQLite'; # fails with DBD::SQLite@1.44 and older
    my @got = Foo->search({ text => { op => 'LIKE', value => '100_%', escape => '_' } });
    is scalar(@got),  1,         'right number';
    is $got[0]->name, 'percent', 'right name';
};

subtest 'use of special characters' => sub {
    subtest 'escape_char single quote' => sub {
        my @got = Foo->search({ text => { op => 'LIKE', value => "100'_", escape => "''" } });
        is scalar(@got),  1,            'right number';
        is $got[0]->name, 'underscore', 'right name';
    };

    if (Foo->driver->dbh->{Driver}->{Name} =~ /mysql|mariadb/i) {
        subtest 'escape_char single quote' => sub {
            my @got = Foo->search({ text => { op => 'LIKE', value => "100'_", escape => "\\'" } });
            is scalar(@got),  1,            'right number';
            is $got[0]->name, 'underscore', 'right name';
        };

        subtest 'escape_char backslash' => sub {
            my @got = Foo->search({ text => { op => 'LIKE', value => '100\\_', escape => '\\\\' } });
            is scalar(@got),  1,            'right number';
            is $got[0]->name, 'underscore', 'right name';
        };
    } else {
        subtest 'escape_char backslash' => sub {
            my @got = Foo->search({ text => { op => 'LIKE', value => '100\\_', escape => '\\' } });
            is scalar(@got),  1,            'right number';
            is $got[0]->name, 'underscore', 'right name';
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
