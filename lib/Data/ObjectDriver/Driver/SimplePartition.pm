package Data::ObjectDriver::Driver::SimplePartition;
use strict;
use warnings;
use base qw( Data::ObjectDriver::Driver::Partition );

use Carp qw( croak );
use Data::Dumper;
use UNIVERSAL::require;

sub init {
    my $driver = shift;
    my %param = @_;
    my $class = delete $param{using} or croak "using is required";
    my @extra = %param;
    $param{get_driver} = _make_get_driver($class, \@extra);
    $driver->SUPER::init(%param);
    return $driver;
}

sub _make_get_driver {
    my($class, $extra) = @_;
    $extra ||= [];
    
    ## Make sure we've loaded the parent class that contains information
    ## about our partitioning scheme.
    $class->require;
    
    my $col = $class->primary_key_tuple->[0];
    my $get_driver = $class->properties->{partition_get_driver}
        or croak "Partitioning driver not defined for $class";

    return sub {
        my($terms) = @_;
        my $parent_id;
        if (ref($terms) eq 'HASH') {
            $parent_id = $terms->{ $col };
        } elsif (ref($terms) eq 'ARRAY') {
            ## An array ref could either be a multiple-column primary key OR
            ## a list of primary keys. With a multiple-column primary key, the
            ## $id is an array ref, where the first column is always the
            ## parent_id.
            $parent_id = ref($terms->[0]) eq 'ARRAY' ?
                $terms->[0][0] : $terms->[0];
        }
        croak "Cannot extract $col from terms ", Dumper($terms)
            unless $parent_id;
        my $parent = $class->driver->lookup($class, $parent_id)
            or croak "Member of $class with ID $parent_id not found";
        return $get_driver->( $parent->partition_id, @$extra );
    };
}

1;
