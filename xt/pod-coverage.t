use strict;
use Test::More;
eval "use Test::Pod::Coverage 1.08";
plan skip_all => "Test::Pod::Coverage 1.08 required for testing POD coverage" if $@;


## Eventually we would be able to test coverage for all modules with
## Test::Pod::all_pod_files(), but let's write the docs first.

my %modules = (
    'Data::ObjectDriver::BaseObject'  => { also_private => [ qr{ \A is_same_array \z }xms ], },
    'Data::ObjectDriver::Errors'      => 1,
    'Data::ObjectDriver::SQL'         => 1,
    'Data::ObjectDriver::Driver::DBD' => 1,
);

plan tests => scalar keys %modules;

while (my ($module, $params) = each %modules) {
    pod_coverage_ok($module, ref $params ? $params : ());
}

