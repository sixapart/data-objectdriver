# so we don't need the Cache::* family installed just to make test...
# lowering the barrier to others hacking on this stuff.

package Cache::Memory;
use strict;
use Storable;

sub new {
    my $class = shift;
    return bless {}, $class;
}

sub remove {
    my ($self, $key) = @_;
    delete $self->{$key};
}

sub thaw {
    my ($self, $key) = @_;
    my $val = $self->{$key};
    return unless defined $val;

    my $magic = eval { Storable::read_magic($val); };
    if ($magic && $magic->{major} && $magic->{major} >= 2) {
        return Storable::thaw($val);
    }

    return $val;
}

sub freeze {
    my ($self, $key, $val) = @_;
    $self->{$key} = ref($val) ? Storable::freeze($val) : $val;
    return 1;
}

1;
