# $Id$

package Data::ObjectDriver::Driver::Cache::Memcached;
use strict;
use warnings;

use base qw( Data::ObjectDriver::Driver::BaseCache );

use Cache::Memcached;
use Carp ();

sub deflate {
    my $driver = shift;
    my($obj) = @_;
    $obj->deflate;
}

sub inflate {
    my $driver = shift;
    my($class, $data) = @_;
    $class->inflate($data);
}

sub add_to_cache            { shift->cache->add(@_)       }
sub update_cache            { shift->cache->set(@_)       }
sub remove_from_cache       { shift->cache->delete(@_)    }
sub get_from_cache          { shift->cache->get(@_)       }
sub get_multi_from_cache    { shift->cache->get_multi(@_) }

1;

__END__

=head1 NAME

Data::ObjectDriver::Driver::Cache::Memcached - object driver for caching objects with memcached

=head1 SYNOPSIS

    package MyObject;
    use base qw( Data::ObjectDriver::BaseObject );

    __PACKAGE__->install_properties({
        ...
        driver => Data::ObjectDriver::Driver::Cache::Memcached->new(
            cache    => Cache::Memcached->new({ servers => \@MEMCACHED_SERVERS }),
            fallback => Data::ObjectDriver::Driver::DBI->new( @$DBI_INFO ),
        ),
        ...
    });

    1;

=head1 DESCRIPTION

I<Data::ObjectDriver::Driver::Cache::Memcached> provides automatic caching of
retrieved objects in your memcached servers, when used in conjunction with your
actual object driver.

=head1 USAGE

=over 4

=item * Data::ObjectDriver::Driver::Cache::Memcached->new( %params )

Required members of C<%params> are:

=over 4

=item * C<cache>

The C<Cache::Memcached> instance representing your pool of memcached servers.
See L<Cache::Memcached>.

=item * C<fallback>

The C<Data::ObjectDriver> object driver from which to request objects that are
not found in your memcached servers.

=back

=back

=head1 SEE ALSO

C<Cache::Memcached>, http://www.danga.com/memcached/

=head1 LICENSE

I<Data::ObjectDriver> is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR & COPYRIGHT

Except where otherwise noted, I<Data::ObjectDriver> is Copyright 2005-2006
Six Apart, cpan@sixapart.com. All rights reserved.

=cut

