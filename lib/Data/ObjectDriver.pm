# $Id$

package Data::ObjectDriver;
use strict;
use base qw( Class::Accessor::Fast );

__PACKAGE__->mk_accessors(qw( pk_generator ));

## TODO:
## refactoring the DBI.pm code
##      - ability to define column => database for each value
##      - plugin interface for doing things like audit, filters
## test suite
## dbh needs to stay around at least as long as sth in iterator
## Memcached::search should fetchonly the IDs, then fetch objects from cache
## multiple column primary keys should allow passing in object,
##  and transparently getting correct column value based on pk column
## add in-memory cache driver (per Apache request)
## refactor Memcached.pm into generic Cache.pm, with Memcached.pm override
## add in DBM.pm
## add in ObjectDriver filters

sub new {
    my $class = shift;
    my $driver = bless {}, $class;
    $driver->init(@_);
    $driver;
}

sub init {
    my $driver = shift;
    my %param = @_;
    $driver->pk_generator($param{pk_generator});
    $driver;
}

sub lookup;
sub lookup_multi;
sub exists;
sub insert;
sub update;
sub remove;
sub search;

1;
