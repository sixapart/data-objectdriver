# $Id$

package Data::ObjectDriver;
use strict;
use base qw( Class::Accessor::Fast );

__PACKAGE__->mk_accessors(qw( pk_generator ));

our $VERSION = '0.01';
our $DEBUG = 0;

## TODO:
## Memcached::search should fetchonly the IDs, then fetch objects from cache
## multiple column primary keys should allow passing in object,
##     and transparently getting correct column value based on pk column

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
    $driver->debug($param{debug});
    $driver;
}

sub debug {
    my $driver = shift;
    print STDERR @_ if $DEBUG;
}

1;
__END__

=head1 NAME

Data::ObjectDriver - Simple, transparent data interface, with caching

=head1 SYNOPSIS

=head1 USAGE

sub lookup;
sub lookup_multi;
sub exists;
sub insert;
sub update;
sub remove;
sub search;

=cut
