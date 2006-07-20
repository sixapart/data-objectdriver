# $Id$

package Data::ObjectDriver::Profiler;
use strict;
use warnings;
use base qw( Class::Accessor::Fast );

use List::Util qw( min );
use Text::Wrap qw( wrap );

__PACKAGE__->mk_accessors(qw( statistics query_log ));

sub new {
    my $class = shift;
    my $profiler = $class->SUPER::new(@_);
    $profiler->reset;
    return $profiler;
}

sub reset {
    my $profiler = shift;
    $profiler->statistics({});
    $profiler->query_log([]);
}

sub increment {
    my $profiler = shift;
    my($driver, $stat) = @_;
    my($type) = ref($driver) =~ /([^:]+)$/;
    $profiler->statistics->{join ':', $type, $stat}++;
}

sub _normalize {
    my($sql) = @_;
    $sql =~ s/^\s*//;
    $sql =~ s/\s*$//;
    $sql =~ s/[\r\n]/ /g;
    return $sql;
}

sub record_query {
    my $profiler = shift;
    my($driver, $sql) = @_;
    $sql = _normalize($sql);
    push @{ $profiler->query_log }, $sql;
    my($type) = $sql =~ /^\s*(\w+)/;
    $profiler->increment($driver, 'total_queries');
    $profiler->increment($driver, 'query_' . lc($type)) if $type;
}

sub query_frequency {
    my $profiler = shift;
    my $log = $profiler->query_log;
    my %freq;
    for my $sql (@$log) {
        $freq{$sql}++;
    }
    return \%freq;
}

sub produce_report {
    my $profiler = shift;
    my $stats = $profiler->statistics;
    my $report = <<REPORT;
Total Queries: $stats->{'DBI:total_queries'}

Queries By Type:
REPORT
    for my $stat (keys %$stats) {
        my($type) = $stat =~ /^DBI:query_(\w+)$/
            or next;
        $report .= sprintf "%-7d %s\n", $stats->{$stat}, uc($type);
    }
    $report .= "\nMost Frequent Queries:\n";
    my $freq = $profiler->query_frequency;
    my @sql = sort { $freq->{$b} <=> $freq->{$a} } keys %$freq;
    local $Text::Wrap::columns = 70;
    for my $sql (@sql[0..min($#sql, 19)]) {
        my $sql_f = wrap('', "        ", $sql);
        $report .= sprintf "%-7d %s\n", $freq->{$sql}, $sql_f;
    }
    return $report;
}

1;
__END__

=head1 NAME

Data::ObjectDriver::Profiler - Query profiling

=head1 SYNOPSIS

    my $profiler = Data::ObjectDriver->profiler;

    my $stats = $profiler->statistics;
    my $total = $stats->{'DBI:total_queries'};

    my $log = $profiler->query_log;

    $profiler->reset;

=head1 USAGE

=head2 $Data::ObjectDriver::PROFILE

To turn on profiling, set I<$Data::ObjectDriver::PROFILE> to a true value.
Alternatively, you can set the I<DOD_PROFILE> environment variable to a true
value before starting your application.

=head2 Data::ObjectDriver->profiler

Profiling is global to I<Data::ObjectDriver>, so the I<Profiler> object is
a global instance variable. To get it, call
I<Data::ObjectDriver-E<gt>profiler>, which returns a
I<Data::ObjectDriver::Profiler> object.

=head2 $profiler->statistics

Returns a hash reference of statistics about the queries that have been
executed.

=head2 $profiler->query_log

Returns a reference to an array of SQL queries as they were handed off to
DBI. This means that placeholder variables are not substituted, so you'll
end up with queries in the query log like
C<SELECT title, difficulty FROM recipe WHERE recipe_id = ?>.

=head2 $profiler->query_frequency

Returns a reference to a hash containing, as keys, all of the SQL statements
in the query log, where the value for each of the keys is a number
representing the number of times the query was executed.

=head2 $profiler->reset

Resets the statistics and the query log.

=head2 $profiler->produce_report

Returns a string containing a pretty report of information about the current
information in the profiler. This is useful to print out at the end of a
web request, for example, or to be installed as a signal handler on an
application.

=cut
