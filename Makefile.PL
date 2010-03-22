# $Id$

use inc::Module::Install;

name('Data-ObjectDriver');
abstract('');
author('Six Apart <cpan@sixapart.com>');
all_from('lib/Data/ObjectDriver.pm');
license('perl');
no_index(directory => 't');

include('ExtUtils::AutoInstall');

requires('DBI');
requires('Class::Accessor::Fast');
requires('Class::Data::Inheritable');
requires('Class::Trigger');
requires('List::Util');
recommends('Text::SimpleTable');
build_requires('Test::Exception');

githubmeta;

# Cache::Memory isn't in Debian, and the tests all SKIP if this isn't here anyway,
# so it's more of a build_recommends than a build_requires, but that doesn't exist,
# so....  commented out:
# build_recommends('Cache::Memory');

auto_include_deps;
author_tests('xt');

WriteAll;
