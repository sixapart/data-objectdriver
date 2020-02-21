requires 'Class::Accessor::Fast';
requires 'Class::Data::Inheritable';
requires 'Class::Trigger';
requires 'DBI';
requires 'List::Util';
requires 'perl', '5.006001';
recommends 'Text::SimpleTable';

on configure => sub {
    requires 'Module::Build::Tiny', '0.035';
};

on build => sub {
    requires 'ExtUtils::MakeMaker', '6.59';
    requires 'Test::Exception';
};

on develop => sub {
    requires 'DBD::SQLite';
    requires 'Text::SimpleTable';
};

on test => sub {
    requires 'version';
};
