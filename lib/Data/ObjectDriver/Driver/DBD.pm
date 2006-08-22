# $Id$

package Data::ObjectDriver::Driver::DBD;
use strict;
use warnings;


sub new {
    my $class = shift;
    my($name) = @_;
    die "No Driver" unless $name;
    my $subclass = join '::', $class, $name;
    eval "use $subclass"; ## no critic
    die $@ if $@;
    bless {}, $subclass;
}

sub init_dbh { }
sub bind_param_attributes { }
sub db_column_name { $_[2] }
sub fetch_id { }
sub offset_implemented { 1 }
sub map_error_code { }

# SQL doesn't define a function to ask a machine of its time in
# unixtime form.  MySQL does, so we override this in the subclass.
# but for sqlite and others, we assume "remote" time is same as local
# machine's time, which is especially true for sqlite.
sub sql_for_unixtime { return time() }

# by default, LIMIT isn't supported on a DELETE.  MySql overrides.
sub can_delete_with_limit { 0 }

# searches are case sensitive by default.  MySql overrides.
sub is_case_insensitive { 0 }

1;
