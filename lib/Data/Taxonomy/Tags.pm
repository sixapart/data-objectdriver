package Data::Taxonomy::Tags;

use strict;
use warnings;

use vars qw($VERSION $ERROR);
$VERSION = '0.05';

use overload
	'""'     => sub { shift->as_string },
	fallback => 1;

# Constants for separator and category
use constant SPLIT  => 0;
use constant JOIN   => 1;

use Data::Taxonomy::Tags::Tag;

=head1 NAME

Data::Taxonomy::Tags - Represents a set of tags for any item

=head1 SYNOPSIS

    use Data::Taxonomy::Tags;
    
    my $tags = Data::Taxonomy::Tags->new('perl tags cpan module system:meta');
    
    print $_, "\n" for $tags->tags;
    
    print $_, "\n" for $tags->categories;

=head1 DESCRIPTION

Data::Taxonomy::Tags will basically take care of managing tags for an
item easier.  You provide it with a string of tags and it'll allow you
to call methods to get all the tags and categories as well as add and
delete tags from the list.

=head2 Methods

=over 12

=item new($string[,\%options])

The first argument is a string of tags.  This string is stripped of any
leading and trailing whitespace.  The second argument, which is optional,
is a hashref of options.

Returns a Data::Taxonomy::Tags object;

=over 24

=item C<< separator => ['\s+', ' '] >>

Specifies the regex pattern (or compiled regex) which will be used to
C<split> the tags apart and the character(s) used between tags when
converting the object back to a string.  Make sure to escape any
special characters in the regex pattern.

If the value is not an arrayref, then the same value is used for both
operations (and is escaped for the regex).

Defaults to C<['\s+', ' ']>.

=item C<< category => [':', ':'] >>

Specifies the regex pattern (or compiled regex) which will be used to
C<split> the tag name from it's optional category and the character(s)
used between the category and tag when converting to a string.  Make
sure to escape any special characters in the regex pattern.

If the value is not an arrayref, then the same value is used for both
operations (and is escaped for the regex).

Defaults to C<[':', ':']>.

=back

=cut
sub new {
    my ($class, $tags, $opt) = @_;
    
    my $self = bless {
        _input       => $tags,
        separator   => ['\s+', ' '],
        category    => [':', ':'],
    }, $class;
    
    if (defined $opt) {
        for (qw(separator category)) {
            if (defined $opt->{$_}) {
                $self->{$_} = ref $opt->{$_} eq 'ARRAY' && @{$opt->{$_}} == 2
                                ? $opt->{$_}
                                : [qr/\Q$opt->{$_}\E/, $opt->{$_}];
            }
        }
    }
    
    $self->add_to_tags($tags);
    
    return $self;
}

=item tags

Returns an array or arrayref (depending on context) of L<Data::Taxonomy::Tags::Tag>
objects.

=cut
sub tags {
    return wantarray && defined $_[0]->{tags}
            ? @{$_[0]->{tags}}
            : $_[0]->{tags};
}

=item add_to_tags($tags)

Processes the string and adds the tag(s) to the object.

=cut
sub add_to_tags {
    my ($self, $input) = @_;
    my @tags = split /$self->{separator}[SPLIT]/, $self->_cleanup($input);
    
    $_ = Data::Taxonomy::Tags::Tag->new($_, { separator => $self->{category} })
        for @tags;
    
    @tags = @{$self->_remove_from_tagset($self->as_string, \@tags)};
    
    push @{$self->{tags}}, @tags;
}

=item remove_from_tags($tags)

Processes the string and removes the tag(s) from the object.

=cut
sub remove_from_tags {
    my ($self, $input) = @_;
    $self->{tags} = $self->_remove_from_tagset($input, [$self->tags]);
}

sub _remove_from_tagset {
    my ($self, $input, $tagset) = @_;
    
    my %tags =   map { $_ => 1 }
               split /$self->{separator}[SPLIT]/, $self->_cleanup($input);
    
    my @result = grep { !$tags{$_} } @$tagset;
    return \@result;
}

=item remove_category($category)

Removes all tags with the specified category.

=cut
sub remove_category {
    my ($self, $category) = @_;
    
    {
        no warnings 'uninitialized';
        @{$self->{tags}} = grep { $_->category ne $category } $self->tags;
    }
}

=item categories

Returns an array or arrayref (depending on context) of the unique categories.

=cut
sub categories {
    my $self = shift;

    my %seen;
    my @cats = grep { defined $_ && !$seen{$_}++ }
                map { $_->category }
                    $self->tags;

    return wantarray ? @cats : \@cats;
}

=item tags_with_category($category)

Returns an array or arrayref (depending on context) of the tags with the
specified category

=cut
sub tags_with_category {
    my ($self, $category) = @_;
    
    my @tags;
    {
        no warnings 'uninitialized';

        @tags =  map { $_->[1]->name }
                grep { $_->[0] eq $category }
                 map { [$_->category, $_] }
                     $self->tags;
    }

    return wantarray ? @tags : \@tags;
}

=item as_string

Returns the tag list as a string (that is, what was given to the constructor).
Overloading is used as well to automatically call this method if the object
is used in a string context.

=cut
sub as_string {
    my $self = shift;
    
    return defined $self->tags
            ? join $self->{separator}[JOIN], $self->tags
            : undef;
}

sub _cleanup {
    my ($self, $str) = @_;
    {
        no warnings 'uninitialized';
        $str =~ s/^\s*//g;
        $str =~ s/\s*$//g;
    }
    return $str;
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


