# $Id$

package Data::ObjectDriver::Driver::Cache::Apache;
use strict;
use warnings;

use base qw( Data::ObjectDriver::Driver::BaseCache );

sub init {
    my $driver = shift;
    my %param  = @_;
    $param{cache} ||= 1; # hack
    $driver->SUPER::init(%param);
}

sub r {
    my $driver = shift;
    if ($INC{"mod_perl.pm"}) {
        return Apache->request;
    } elsif ($INC{"mod_perl2.pm"}) {
        return Apache2::RequestUtil->request;
    } else {
        die "Not running on mod_perl environment.";
    }
}

sub get_from_cache {
    my $r = $_[0]->r or return;
    $r->pnotes($_[1]);
}

sub add_to_cache {
    my $r = $_[0]->r or return;
    $r->pnotes($_[1], $_[2]);
}

sub update_cache {
    my $r = $_[0]->r or return;
    $r->pnotes($_[1], $_[2]);
}

sub remove_from_cache {
    my $r = $_[0]->r or return;
    delete $r->pnotes->{$_[1]};
}

1;
