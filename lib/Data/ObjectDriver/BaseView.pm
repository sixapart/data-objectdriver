# $Id$

package Data::ObjectDriver::BaseView;
use strict;
use base qw( Data::ObjectDriver::BaseObject );

use Carp ();

sub search {
    my $class = shift;
    my($terms, $args) = @_;
    $args->{sql_statement} = $class->base_statement;
    $class->_proxy('search', $terms, $args)
}

1;
