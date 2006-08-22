package Data::Taxonomy::Tags::Tag;

use overload
	'""'     => sub { shift->as_string },
	fallback => 1;

# Constants for separator and category
use constant SPLIT  => 0;
use constant JOIN   => 1;

=head1 NAME

Data::Taxonomy::Tags::Tag - Represents a single tag

=head1 SYNOPSIS

    print $tag->name, " (category: ", $tag->category, ")\n";

=head1 DESCRIPTION

Data::Taxonomy::Tags::Tag represents a single tag for a Data::Taxonomy::Tags
object.

=head2 Methods

=over 12

=item new

Creates a new instance of the class representing a single tag.  Requires two
arguments (the input tag to parse and separator arrayref).  You shouldn't
have to use this method yourself.

=cut
sub new {
    my ($class, $tag, $opt) = @_;

    my $self = bless {
        input       => $tag,
        separator   => $opt->{separator},
    }, $class;
    
    $self->_process;
    
    *name = \&tag;
    
    return $self;
}

=item tag

=item name

Returns the name of the tag (that is, the tag itself) sans the category bit.

=cut
sub tag {
    my ($self, $v) = @_;
    $self->{tag} = $v
        if defined $v;
    return $self->{tag};
}

=item category

Returns the category the tag is in.  If there is no category, then undef
is returned;

=cut
sub category {
    my ($self, $v) = @_;
    $self->{category} = $v
        if defined $v;
    return $self->{category};
}

sub _process {
    my $self = shift;
    my ($one, $two) = split /$self->{separator}[SPLIT]/, $self->{input};
    if (defined $one and defined $two) {
        $self->tag($two);
        $self->category($one);
    }
    elsif (defined $one and not defined $two) {
        $self->tag($one);
    }
    else {
        # Ack!  Weird data.
        $self->tag($self->{input});
    }
}

=item as_string

Returns the full tag as a string (that is, the category, the category seperator,
and the tag name all concatenated together).  Overloading is used as well to
automatically call this method if the object is used in a string context.

=cut
sub as_string {
    my $self = shift;
        
    return defined $self
            ? defined $self->category
                    ? $self->category . $self->{separator}[JOIN] . $self->tag
                    : $self->tag
            : undef;
}

=back

=head1 BUGS

All bugs, open and resolved, are handled by RT at
L<https://rt.cpan.org/NoAuth/Bugs.html?Dist=Data-Taxonomy-Tags>.

Please report all bugs via
L<https://rt.cpan.org/NoAuth/ReportBug.html?Queue=Data-Taxonomy-Tags>.

=head1 LICENSE

Copyright 2005, Thomas R. Sibley.

You may use, modify, and distribute this package under the same terms as Perl itself.

=head1 AUTHOR

Thomas R. Sibley, L<http://zulutango.org:82/>

=cut

42;


