[![Build Status](https://travis-ci.org/sixapart/data-objectdriver.svg?branch=master)](https://travis-ci.org/sixapart/data-objectdriver) [![Coverage Status](https://img.shields.io/coveralls/sixapart/data-objectdriver/master.svg?style=flat)](https://coveralls.io/r/sixapart/data-objectdriver?branch=master)
# NAME

Data::ObjectDriver - Simple, transparent data interface, with caching

# SYNOPSIS

    ## Set up your database driver code.
    package FoodDriver;
    sub driver {
        Data::ObjectDriver::Driver::DBI->new(
            dsn      => 'dbi:mysql:dbname',
            username => 'username',
            password => 'password',
        )
    }

    ## Set up the classes for your recipe and ingredient objects.
    package Recipe;
    use base qw( Data::ObjectDriver::BaseObject );
    __PACKAGE__->install_properties({
        columns     => [ 'recipe_id', 'title' ],
        datasource  => 'recipe',
        primary_key => 'recipe_id',
        driver      => FoodDriver->driver,
    });

    package Ingredient;
    use base qw( Data::ObjectDriver::BaseObject );
    __PACKAGE__->install_properties({
        columns     => [ 'ingredient_id', 'recipe_id', 'name', 'quantity' ],
        datasource  => 'ingredient',
        primary_key => [ 'recipe_id', 'ingredient_id' ],
        driver      => FoodDriver->driver,
    });

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

    ## Shorthand constructor
    my $ingredient = Ingredient->new(recipe_id=> $recipe->id,
                                     name => 'Milk',
                                     quantity => 2);

# DESCRIPTION

_Data::ObjectDriver_ is an object relational mapper, meaning that it maps
object-oriented design concepts onto a relational database.

It's inspired by, and descended from, the _MT::ObjectDriver_ classes in
Six Apart's Movable Type and TypePad weblogging products. But it adds in
caching and partitioning layers, allowing you to spread data across multiple
physical databases, without your application code needing to know where the
data is stored.

# METHODOLOGY

_Data::ObjectDriver_ provides you with a framework for building
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

would take the following path through the _Data::ObjectDriver_ framework:

1. The caching layer would look up the object with the given primary key in all
of the specified memcached servers.

    If the object was found in the cache, it would be returned immediately.

    If the object was not found in the cache, the caching layer would fall back
    to the driver listed in the _fallback_ setting: the partitioning layer.

2. The partitioning layer does not know how to look up objects by itself--all
it knows how to do is to give back a driver that _does_ know how to look
up objects in a backend datastore.

    In our example above, imagine that we're partitioning our ingredient data
    based on the recipe that the ingredient is found in. For example, all of
    the ingredients for a "Banana Milkshake" would be found in one partition;
    all of the ingredients for a "Chocolate Sundae" might be found in another
    partition.

    So the partitioning layer needs to tell us which partition to look in to
    load the ingredients for _$recipe->recipe\_id_. If we store a
    _partition\_id_ column along with each _$recipe_ object, that information
    can be loaded very easily, and the partitioning layer will then
    instantiate a _DBI_ driver that knows how to load an ingredient from
    that recipe.

3. Using the _DBI_ driver that the partitioning layer created,
_Data::ObjectDriver_ can look up the ingredient with the specified primary
key. It will return that key back up the chain, giving each layer a chance
to do something with it.
4. The caching layer, when it receives the object loaded in Step 3, will
store the object in memcached.
5. The object will be passed back to the caller. Subsequent lookups of that
same object will come from the cache.

# HOW IS IT DIFFERENT?

_Data::ObjectDriver_ differs from other similar frameworks
(e.g. [Class::DBI](https://metacpan.org/pod/Class%3A%3ADBI)) in a couple of ways:

- It has built-in support for caching.
- It has built-in support for data partitioning.
- Drivers are attached to classes, not to the application as a whole.

    This is essential for partitioning, because your partition drivers need
    to know how to load a specific class of data.

    But it can also be useful for caching, because you may find that it doesn't
    make sense to cache certain classes of data that change constantly.

- The driver class != the base object class.

    All of the object classes you declare will descend from
    _Data::ObjectDriver::BaseObject_, and all of the drivers you instantiate
    or subclass will descend from _Data::ObjectDriver_ itself.

    This provides a useful distinction between your data/classes, and the
    drivers that describe how to **act** on that data, meaning that an
    object based on _Data::ObjectDriver::BaseObject_ is not tied to any
    particular type of driver.

# USAGE

## Class->lookup($id)

Looks up/retrieves a single object with the primary key _$id_, and returns
the object.

_$id_ can be either a scalar or a reference to an array, in the case of
a class with a multiple column primary key.

## Class->lookup\_multi(\\@ids)

Looks up/retrieves multiple objects with the IDs _\\@ids_, which should be
a reference to an array of IDs. As in the case of _lookup_, an ID can
be either a scalar or a reference to an array.

Returns a reference to an array of objects **in the same order** as the IDs
you passed in. Any objects that could not successfully be loaded will be
represented in that array as an `undef` element.

So, for example, if you wanted to load 2 objects with the primary keys
`[ 5, 3 ]` and `[ 4, 2 ]`, you'd call _lookup\_multi_ like this:

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

where _$object_ is an instance of _Class_.

## Class->search(\\%terms \[, \\%options \])

Searches for objects matching the terms _%terms_. In list context, returns
an array of matching objects; in scalar context, returns a reference to
a subroutine that acts as an iterator object, like so:

    my $iter = Ingredient->search({ recipe_id => 5 });
    while (my $ingredient = $iter->()) {
        ...
    }

`$iter` is blessed in [Data::ObjectDriver::Iterator](https://metacpan.org/pod/Data%3A%3AObjectDriver%3A%3AIterator) package, so the above
could also be written:

    my $iter = Ingredient->search({ recipe_id => 5 });
    while (my $ingredient = $iter->next()) {
        ...
    }

The keys in _%terms_ should be column names for the database table
modeled by _Class_ (and the values should be the desired values for those
columns).

_%options_ can contain:

- sort

    The name of a column to use to sort the result set.

    Optional.

- direction

    The direction in which you want to sort the result set. Must be either
    `ascend` or `descend`.

    Optional.

- limit

    The value for a _LIMIT_ clause, to limit the size of the result set.

    Optional.

- offset

    The offset to start at when limiting the result set.

    Optional.

- fetchonly

    A reference to an array of column names to fetch in the _SELECT_ statement.

    Optional; the default is to fetch the values of all of the columns.

- for\_update

    If set to a true value, the _SELECT_ statement generated will include a
    _FOR UPDATE_ clause.

- comment

    A sql comment to watermark the SQL query.

- window\_size

    Used when requesting an iterator for the search method and selecting
    a large result set or a result set of unknown size. In such a case,
    no LIMIT clause is assigned, which can load all available objects into
    memory. Specifying `window_size` will load objects in manageable chunks.
    This will also cause any caching driver to be bypassed for issuing
    the search itself. Objects are still placed into the cache upon load.

    This attribute is ignored when the search method is invoked in an array
    context, or if a `limit` attribute is also specified that is smaller than
    the `window_size`.

## Class->search(\\@terms \[, \\%options \])

This is an alternative calling signature for the search method documented
above. When providing an array of terms, it allows for constructing complex
expressions that mix 'and' and 'or' clauses. For example:

    my $iter = Ingredient->search([ { recipe_id => 5 },
        -or => { calories => { value => 300, op => '<' } } ]);
    while (my $ingredient = $iter->()) {
        ...
    }

Supported logic operators are: '-and', '-or', '-and\_not', '-or\_not'.

## Class->add\_trigger($trigger, \\&callback)

Adds a trigger to all objects of class _Class_, such that when the event
_$trigger_ occurs to any of the objects, subroutine `&callback` is run. Note
that triggers will not occur for instances of _subclasses_ of _Class_, only
of _Class_ itself. See TRIGGERS for the available triggers.

## Class->call\_trigger($trigger, \[@callback\_params\])

Invokes the triggers watching class _Class_. The parameters to send to the
callbacks (in addition to _Class_) are specified in _@callback\_params_. See
TRIGGERS for the available triggers.

## $obj->save

Saves the object _$obj_ to the database.

If the object is not yet in the database, _save_ will automatically
generate a primary key and insert the record into the database table.
Otherwise, it will update the existing record.

If an error occurs, _save_ will _croak_.

Internally, _save_ calls _update_ for records that already exist in the
database, and _insert_ for those that don't.

## $obj->remove

Removes the object _$obj_ from the database.

If an error occurs, _remove_ will _croak_.

## Class->remove(\\%terms, \\%args)

Removes objects found with the _%terms_. So it's a shortcut of:

    my @obj = Class->search(\%terms, \%args);
    for my $obj (@obj) {
        $obj->remove;
    }

However, when you pass `nofetch` option set to `%args`, it won't
create objects with `search`, but issues _DELETE_ SQL directly to
the database.

    ## issues "DELETE FROM tbl WHERE user_id = 2"
    Class->remove({ user_id => 2 }, { nofetch => 1 });

This might be much faster and useful for tables without Primary Key,
but beware that in this case **Triggers won't be fired** because no
objects are instantiated.

## Class->bulk\_insert(\[col1, col2\], \[\[d1,d2\], \[d1,d2\]\]);

Bulk inserts data into the underlying table.  The first argument
is an array reference of columns names as specified in install\_properties

## $obj->add\_trigger($trigger, \\&callback)

Adds a trigger to the object _$obj_, such that when the event _$trigger_
occurs to the object, subroutine `&callback` is run. See TRIGGERS for the
available triggers. Triggers are invoked in the order in which they are added.

## $obj->call\_trigger($trigger, \[@callback\_params\])

Invokes the triggers watching all objects of _$obj_'s class and the object
_$obj_ specifically for trigger event _$trigger_. The additional parameters
besides _$obj_, if any, are passed as _@callback\_params_. See TRIGGERS for
the available triggers.

# TRIGGERS

_Data::ObjectDriver_ provides a trigger mechanism by which callbacks can be
called at certain points in the life cycle of an object. These can be set on a
class as a whole or individual objects (see USAGE).

Triggers can be added and called for these events:

- pre\_save -> ($obj, $orig\_obj)

    Callbacks on the _pre\_save_ trigger are called when the object is about to be
    saved to the database. For example, use this callback to translate special code
    strings into numbers for storage in an integer column in the database. Note that this hook is also called when you `remove` the object.

    Modifications to _$obj_ will affect the values passed to subsequent triggers
    and saved in the database, but not the original object on which the _save_
    method was invoked.

- post\_save -> ($obj, $orig\_obj)

    Callbaks on the _post\_save_ triggers are called after the object is
    saved to the database. Use this trigger when your hook needs primary
    key which is automatically assigned (like auto\_increment and
    sequence). Note that this hooks is **NOT** called when you remove the
    object.

- pre\_insert/post\_insert/pre\_update/post\_update/pre\_remove/post\_remove -> ($obj, $orig\_obj)

    Those triggers are fired before and after $obj is created, updated and
    deleted.

- post\_load -> ($obj)

    Callbacks on the _post\_load_ trigger are called when an object is being
    created from a database query, such as with the _lookup_ and _search_ class
    methods. For example, use this callback to translate the numbers your
    _pre\_save_ callback caused to be saved _back_ into string codes.

    Modifications to _$obj_ will affect the object passed to subsequent triggers
    and returned from the loading method.

    Note _pre\_load_ should only be used as a trigger on a class, as the object to
    which the load is occurring was not previously available for triggers to be
    added.

- pre\_search -> ($class, $terms, $args)

    Callbacks on the _pre\_search_ trigger are called when a content addressed
    query for objects of class _$class_ is performed with the _search_ method.
    For example, use this callback to translate the entry in _$terms_ for your
    code string field to its appropriate integer value.

    Modifications to _$terms_ and _$args_ will affect the parameters to
    subsequent triggers and what objects are loaded, but not the original hash
    references used in the _search_ query.

    Note _pre\_search_ should only be used as a trigger on a class, as _search_ is
    never invoked on specific objects.

    >     The return values from your callbacks are ignored.
    >
    >     Note that the invocation of callbacks is the responsibility of the object
    >     driver. If you implement a driver that does not delegate to
    >     _Data::ObjectDriver::Driver::DBI_, it is _your_ responsibility to invoke the
    >     appropriate callbacks with the _call\_trigger_ method.

# PROFILING

For performance tuning, you can turn on query profiling by setting
_$Data::ObjectDriver::PROFILE_ to a true value. Or, alternatively, you can
set the _DOD\_PROFILE_ environment variable to a true value before starting
your application.

To obtain the profile statistics, get the global
_Data::ObjectDriver::Profiler_ instance:

    my $profiler = Data::ObjectDriver->profiler;

Then see the documentation for _Data::ObjectDriver::Profiler_ to see the
methods on that class.

In some applications there are phases of execution in which no I/O
operations should occur, but sometimes it's difficult to tell when,
where, or if those I/O operations are happening.  One approach to
surfacing these situations is to set, either globally or locally,
the $Data::ObjectDriver::RESTRICT\_IO flag.  If set, this will tell
Data::ObjectDriver to die with some context rather than executing
network calls for data.

# TRANSACTIONS

Transactions are supported by Data::ObjectDriver's default drivers. So each
Driver is capable to deal with transactional state independently. Additionally
<Data::ObjectDriver::BaseObject> class know how to turn transactions switch on
for all objects.

In the case of a global transaction all drivers used during this time are put
in a transactional state until the end of the transaction.

## Example

    ## start a transaction
    Data::ObjectDriver::BaseObject->begin_work;

    $recipe = Recipe->new;
    $recipe->title('lasagnes');
    $recipe->save;

    my $ingredient = Ingredient->new;
    $ingredient->recipe_id($recipe->recipe_id);
    $ingredient->name("more layers");
    $ingredient->insert;
    $ingredient->remove;

    if ($you_are_sure) {
        Data::ObjectDriver::BaseObject->commit;
    }
    else {
        ## erase all trace of the above
        Data::ObjectDriver::BaseObject->rollback;
    }

## Driver implementation

Drivers have to implement the following methods:

- begin\_work to initialize a transaction
- rollback
- commit

## Nested transactions

Are not supported and will result in warnings and the inner transactions
to be ignored. Be sure to **end** each transaction and not to let et long
running transaction open (i.e you should execute a rollback or commit for
each open begin\_work).

## Transactions and DBI

In order to make transactions work properly you have to make sure that
the `$dbh` for each DBI drivers are shared among drivers using the same
database (basically dsn).

One way of doing that is to define a get\_dbh() subref in each DBI driver
to return the same dbh if the dsn and attributes of the connection are
identical.

The other way is to use the new configuration flag on the DBI driver that
has been added specifically for this purpose: `reuse_dbh`.

    ## example coming from the test suite
    __PACKAGE__->install_properties({
        columns => [ 'recipe_id', 'partition_id', 'title' ],
        datasource => 'recipes',
        primary_key => 'recipe_id',
        driver => Data::ObjectDriver::Driver::Cache::Cache->new(
            cache => Cache::Memory->new,
            fallback => Data::ObjectDriver::Driver::DBI->new(
                dsn      => 'dbi:SQLite:dbname=global.db',
                reuse_dbh => 1,  ## be sure that the corresponding dbh is shared
            ),
        ),
    });

# EXAMPLES

## A Partitioned, Caching Driver

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

# FORK SAFETY

As of version 0.21, _Data::ObjectDriver_ resets internal database handles
after _fork(2)_ is called, but only if [POSIX::AtFork](https://metacpan.org/pod/POSIX%3A%3AAtFork) module is installed.
Otherwise, _Data::ObjectDriver_ is not fork-safe.

# SUPPORTED DATABASES

_Data::ObjectDriver_ is very modular and it's not very difficult to add new drivers.

- MySQL is well supported and has been heavily tested.
- PostgreSQL has been used in production and should just work, too.
- SQLite is supported, but YMMV depending on the version. This is the
backend used for the test suite.
- Oracle support has been added in 0.06

# LICENSE

_Data::ObjectDriver_ is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR & COPYRIGHT

Except where otherwise noted, _Data::ObjectDriver_ is Copyright 2005-2006
Six Apart, cpan@sixapart.com. All rights reserved.
