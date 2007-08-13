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
    my $driver = shift;
    my $r = $driver->r or return;

    $driver->start_query('APACHECACHE_GET ?', \@_);
    my $ret = $r->pnotes($_[0]);
    $driver->end_query(undef);

    return if !defined $ret;
    return $ret;
}

sub add_to_cache {
    my $driver = shift;
    my $r = $driver->r or return;

    $driver->start_query('APACHECACHE_ADD ?,?', \@_);
    my $ret = $r->pnotes($_[0], $_[1]);
    $driver->end_query(undef);

    return if !defined $ret;
    return $ret;
}

sub update_cache {
    my $driver = shift;
    my $r = $driver->r or return;

    $driver->start_query('APACHECACHE_UPDATE ?,?', \@_);
    my $ret = $r->pnotes($_[0], $_[1]);
    $driver->end_query(undef);

    return if !defined $ret;
    return $ret;
}

sub remove_from_cache {
    my $driver = shift;
    my $r = $driver->r or return;

    $driver->start_query('APACHECACHE_REMOVE ?', \@_);
    my $ret = delete $r->pnotes->{$_[0]};
    $driver->end_query(undef);

    return if !defined $ret;
    return $ret;
}

1;
