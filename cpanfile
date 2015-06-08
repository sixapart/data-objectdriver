requires 'Class::Accessor::Fast';
requires 'Class::Data::Inheritable';
requires 'Class::Trigger';
requires 'DBI';
requires 'List::Util';
requires 'perl', '5.006001';
recommends 'Text::SimpleTable';

on build => sub {
    requires 'ExtUtils::MakeMaker', '6.59';
    requires 'Test::Exception';
};

on develop => sub {
   requires 'DBD::SQLite';
   requires 'Text::SimpleTable';
};
