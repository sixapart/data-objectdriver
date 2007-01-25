# $Id: YUID.pm 1029 2005-11-22 07:11:22Z btrott $

package Data::YUID;
use strict;

our $VERSION = '0.01';

1;
__END__

=head1 NAME

Data::YUID - Distributed ID generator ("Yet another Unique ID")

=head1 SYNOPSIS

    ## Generating a unique ID within a particular process...
    use Data::YUID::Generator;
    my $generator = Data::YUID::Generator->new;
    my $id = $generator->get_id;

    ## Generating a unique ID from a set of distributed servers...
    use Data::YUID::Client;
    my $client = Data::YUID::Client->new(
            servers => [
                '192.168.100.4:11001',
                '192.168.100.5:11001',
            ],
        );
    my $id = $client->get_id;

=head1 DESCRIPTION

I<Data::YUID> ("Yet another Unique ID") is an ID allocation engine that can
be used both in client/server mode--with a set of distributed servers--and
within a single process.

It generates IDs with temporal and spatial uniqueness. These IDs are less
universally unique than Type-1 UUIDs, because they have only 64 bits of
usable ID space split up between the various parts. Currently, ID
generation uses this split:
 
16 bits of host ID (akin to a locally provisioned MAC address)
36 bits of time in seconds since the epoch (currently Jan 1 2000 00:00 GMT)
12 bits of serial incrementor
 
Given the following restrictions, a YUID generator will generate guaranteed
globally (within your control) unique IDs:

=over 4

=item 1. no two hosts with the same host ID are running simultaneously

=item 2. for a given ID namespace, no more than (T - S) * (2^12) IDs have been generated, where T = current time and S = start time of generator

=back
 
The size of the incrementor is dependent on the rate of request. For IDs
with a short lifetime but high request rate, you could use fewer time bits
and more serial bits.

=head1 USAGE

See L<Data::YUID::Client> and L<Data::YUID::Generator> for usage details.

=head1 LICENSE

I<Data::YUID> is free software; you may redistribute it and/or modify it
under the same terms as Perl itself.

=head1 AUTHOR & COPYRIGHT

Except where otherwise noted, I<Data::YUID> is Copyright 2005 Six Apart,
cpan@sixapart.com. All rights reserved.

=cut
