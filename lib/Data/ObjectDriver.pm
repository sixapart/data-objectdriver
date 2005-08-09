# $Id$

package Data::ObjectDriver;
use strict;
use base qw( Class::Accessor::Fast );

__PACKAGE__->mk_accessors(qw( pk_generator ));

our $VERSION = '0.01';
our $DEBUG = 0;

use Data::Dumper ();

sub new {
    my $class = shift;
    my $driver = bless {}, $class;
    $driver->init(@_);
    $driver;
}

sub init {
    my $driver = shift;
    my %param = @_;
    $driver->pk_generator($param{pk_generator});
    $driver;
}

sub debug {
    my $driver = shift;
    return unless $DEBUG;
    if (@_ == 1 && !ref($_[0])) {
        print STDERR @_;
    } else {
        local $Data::Dumper::Indent = 1;
        print STDERR Data::Dumper::Dumper(@_);
    }
}


1;
__END__

=head1 NAME

Data::ObjectDriver - Simple, transparent data interface, with caching

=head1 SYNOPSIS

    ## Set up your database driver code.
    package FoodDriver;
    sub driver {
        Data::ObjectDriver::Driver::DBI->new(
            dsn      => 'dbi:mysql:dbname',
            username => 'username',
            password => 'password',
    }

    ## Set up the classes for your recipe and ingredient objects.
    package Recipe;
    use base qw( Data::ObjectDriver::BaseObject );
    __PACKAGE__->install_properties(
        columns     => [ 'recipe_id', 'title' ],
        datasource  => 'recipe',
        primary_key => 'recipe_id',
        driver      => FoodDriver->driver,
    );

    package Ingredient;
    use base qw( Data::ObjectDriver::BaseObject );
    __PACKAGE__->install_properties(
        columns     => [ 'ingredient_id', 'recipe_id', 'name', 'quantity' ],
        datasource  => 'ingredient',
        primary_key => [ 'recipe_id', 'ingredient_id' ],
        driver      => FoodDriver->driver,
    );

    ## And now, use them!
    my $recipe = Recipe->new;
    $recipe->title('Banana Milkshake');
    $recipe->save;

    my $ingredient = Ingredient->new;
    $ingredient->recipe_id($recipe->id);
    $ingredient->name('Bananas');
    $ingredient->quantity(5);
    $ingredient->save;

    ## Needs more bananas!
    $ingredient->quantity(10);
    $ingredient->save;

=head1 INTRODUCTION

=head2 How to set it up

=over 4

=item I<Set up a database.>

You must have an existing 

=item I<Set up a cache. (optional)>

If you'd like to use the built-in caching features, you'll need a cache.
I<Data::ObjectDriver> supports I<Cache::Memcached> and any of the
I<Cache.pm> subclasses.

=item I<Set up a schema for your objects to be stored in.>

=item I<Set up the classes for your objects.>

=back

=head1 METHODOLOGY

I<Data::ObjectDriver> provides you with a framework for building
database-backed applications. It provides built-in support for object
caching and database partitioning, and uses a layered approach to allow
building very sophisticated database interfaces without a lot of code.

You can build a driver that uses any number of caching layers, plus a
partitioning layer, then a final layer that actually knows how to load
data from a backend datastore.

For example, the following code:

    my $driver = Data::ObjectDriver::Driver::Cache::Memcached->new(
            cache    => Cache::Memcached->new(
                            servers => [ '127.0.0.1:11211' ],
                        ),
            fallback => Data::ObjectDriver::Driver::Partition->new(
                            get_driver => \&get_driver,
                        ),
    );

creates a new driver that supports both caching (using memcached) and
partitioning.

It's useful to demonstrate the flow of a sample request through this
driver framework. The following code:

    my $ingredient = Ingredient->lookup([ $recipe->recipe_id, 1 ]);

would take the following path through the I<Data::ObjectDriver> framework:

=over 4

=item 1.

The caching layer would look up the object with the given primary key in all
of the specified memcached servers.

If the object was found in the cache, it would be returned immediately.

If the object was not found in the cache, the caching layer would fall back
to the driver listed in the I<fallback> setting: the partitioning layer.

=item 2.

The partitioning layer does not know how to look up objects by itself--all
it knows how to do is to give back a driver that I<does> know how to loko
up objects in a backend datastore.

In our example above, imagine that we're partitioning our ingredient data
based on the recipe that the ingredient is found in. For example, all of
the ingredients for a "Banana Milkshake" would be found in one partition;
all of the ingredients for a "Chocolate Sundae" might be found in another
partition.

So the partitioning layer needs to tell us which partition to look in to
load the ingredients for I<$recipe-E<gt>recipe_id>. If we store a
I<partition_id> column along with each I<$recipe> object, that information
can be loaded very easily, and the partitioning layer will then
instantiate a I<DBI> driver that knows how to load an ingredient from
that recipe.

=item 3.

Using the I<DBI> driver that the partitioning layer created,
I<Data::ObjectDriver> can look up the ingredient with the specified primary
key. It will return that key back up the chain, giving each layer a chance
to do something with it.

=item 4.

The caching layer, when it receives the object loaded in Step 3, will
store the object in memcached.

=item 5.

The object will be passed back to the caller. Subsequent lookups of that
same object will come from the cache.

=back

=head1 HOW IS IT DIFFERENT?

I<Data::ObjectDriver> differs from other similar frameworks
(e.g. L<Class::DBI>) in a couple of ways:

=over 4

=item * It has built-in support for caching.

=item * It has built-in support for data partitioning.

=item * Drivers are attached to classes, not to the application as a whole.

This is essential for partitioning, because your partition drivers need
to know how to load a specific class of data.

But it can also be useful for caching, because you may find that it doesn't
make sense to cache certain classes of data that change constantly.

=item * The driver class != the base object class.

All of the object classes you declare will descend from
I<Data::ObjectDriver::BaseObject>, and all of the drivers you instantiate
or subclass will descend from I<Data::ObjectDriver> itself.

This provides a useful distinction between your data/classes, and the
drivers that describe how to B<act> on that data, meaning that an
object based on I<Data::ObjectDriver::BaseObject> is not tied to any
particular type of driver.

=back

=head1 USAGE

=head2 Class->lookup($id)

Looks up/retrieves a single object with the primary key I<$id>, and returns
the object.

I<$id> can be either a scalar or a reference to an array, in the case of
a class with a multiple column primary key.

=head2 Class->lookup_multi(\@ids)

Looks up/retrieves multiple objects with the IDs I<\@ids>, which should be
a reference to an array of IDs. As in the case of I<lookup>, an ID can
be either a scalar or a reference to an array.

Returns a reference to an array of objects in the same order as the IDs
you passed in. Any objects that could not successfully be loaded will be
represented in that array as an C<undef> element.

So, for example, if you wanted to load 2 objects with the primary keys
C<[ 5, 3 ]> and C<[ 4, 2 ]>, you'd call I<lookup_multi> like this:

    Class->lookup_multi([
        [ 5, 3 ],
        [ 4, 2 ],
    ]);

And if the first object in that list could not be loaded successfully,
you'd get back a reference to an array like this:

    [
        undef,
        $object
    ]

where I<$object> is an instance of I<Class>.

=head2 Class->search(\%terms [, \%options ])

=head2 $obj->save

=head2 $obj->insert

=head2 $obj->update

=head2 $obj->remove

=head1 EXAMPLES

=head2 A Partitioned, Caching Driver

    package Ingredient;
    use strict;
    use base qw( Data::ObjectDriver::BaseObject );

    use Data::ObjectDriver::Driver::DBI;
    use Data::ObjectDriver::Driver::Partition;
    use Data::ObjectDriver::Driver::Cache::Cache;
    use Cache::Memory;
    use Carp;

    our $IDs;

    __PACKAGE__->install_properties({
        columns     => [ 'ingredient_id', 'recipe_id', 'name', 'quantity', ],
        datasource  => 'ingredients',
        primary_key => [ 'recipe_id', 'ingredient_id' ],
        driver      =>
            Data::ObjectDriver::Driver::Cache::Cache->new(
                cache    => Cache::Memory->new( namespace => __PACKAGE__ ),
                fallback =>
                    Data::ObjectDriver::Driver::Partition->new(
                        get_driver   => \&get_driver,
                        pk_generator => \&generate_pk,
                    ),
            ),
    });

    sub get_driver {
        my($terms) = @_;
        my $recipe;
        if (ref $terms eq 'HASH') {
            my $recipe_id = $terms->{recipe_id}
                or Carp::croak("recipe_id is required");
            $recipe = Recipe->lookup($recipe_id);
        } elsif (ref $terms eq 'ARRAY') {
            $recipe = Recipe->lookup($terms->[0]);
        }
        Carp::croak("Unknown recipe") unless $recipe;
        Data::ObjectDriver::Driver::DBI->new(
            dsn          => 'dbi:mysql:database=cluster' . $recipe->cluster_id,
            username     => 'foo',
            pk_generator => \&generate_pk,
        );
    }

    sub generate_pk {
        my($obj) = @_;
        $obj->ingredient_id(++$IDs{$obj->recipe_id});
        1;
    }

    1;

=cut
