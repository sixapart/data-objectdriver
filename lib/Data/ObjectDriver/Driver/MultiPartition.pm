package Data::ObjectDriver::Driver::MultiPartition;
use strict;
use base qw( Data::ObjectDriver );

__PACKAGE__->mk_accessors(qw( partitions ));

sub init {
    my $driver = shift;
    $driver->SUPER::init(@_);
    my %param = @_;
    $driver->partitions($param{partitions});
    return $driver;
}

sub search {
    my $driver = shift;
    my($class, $terms, $args) = @_;
    
    my @objs;
    for my $partition (@{ $driver->partitions }) {
        push @objs, $partition->search($class, $terms, $args);
    }
    return @objs;
}

1;

__END__

=head1 NAME

Data::ObjectDriver::Driver::MultiPartition - Search thru partitioned objects without
the partition_key

=head1 DESCRIPTION

I<Data::ObjectDriver::Driver::MultiPartition> is used internally by 
I<Data::ObjectDriver::Driver::SimplePartition>
