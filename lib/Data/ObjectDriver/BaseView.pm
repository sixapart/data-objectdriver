# $Id$

package Data::ObjectDriver::BaseView;
use strict;
use base qw( Data::ObjectDriver::BaseObject );

use Carp ();
use Storable;

sub search {
    my $class = shift;
    my($terms, $args) = @_;
    $args->{sql_statement} = $class->base_statement($terms, $args);
    $args  = Storable::dclone($args);

    my %cols = map { $_ => 1 } @{ $class->properties->{columns} }; 
    my %having;
    for my $key (keys %$terms) {
        if ($cols{$key}) {
            next unless $args->{sql_statement}->aggregates->{$key};
            # Don't need to delete from $term, because D::OD ignores
            # it anyway when used as View class
            $having{$key} = $terms->{$key};
        }
    }
    $args->{having} = \%having;
    
    $class->_proxy('search', $terms, $args)
}

1;
