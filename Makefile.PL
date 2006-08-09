# $Id$

use inc::Module::Install;

name('Data-ObjectDriver');
abstract('');
author('Six Apart <cpan@sixapart.com>');
version_from('lib/Data/ObjectDriver.pm');
license('perl');
no_index(directory => 't');
sign(1);

include('ExtUtils::AutoInstall');

requires('DBI');
requires('Class::Accessor::Fast');
requires('Class::Data::Inheritable');
requires('Class::Trigger');
requires('List::Util');
recommends('Text::SimpleTable');
build_requires('Test::Exception');
build_requires('UNIVERSAL::require');
build_requires('Cache::Memory');

auto_include();
auto_install();

&WriteAll;
