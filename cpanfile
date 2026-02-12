requires 'Class::Accessor::Fast';
requires 'Class::Data::Inheritable';
requires 'Class::Trigger';
requires 'DBI';
requires 'List::Util';
requires 'perl', '5.008001';
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
    requires 'Tie::IxHash';
    requires 'Digest::SHA';
};

feature 'test_sqlite', 'Test SQLite' => sub {
    requires 'DBD::SQLite';
};

feature 'test_mysql', 'Test MySQL' => sub {
    requires 'DBD::mysql';
    requires 'Test::mysqld';
    requires 'SQL::Translator';
};

feature 'test_mariadb', 'Test MariaDB' => sub {
    requires 'DBD::MariaDB';
    requires 'Test::mysqld';
    requires 'SQL::Translator';
};

feature 'test_postgresql', 'Test PostgreSQL' => sub {
    requires 'DBD::Pg';
    requires 'Test::PostgreSQL';
    requires 'SQL::Translator';
};

feature 'test_fork', 'Test Fork' => sub {
    requires 'DBI', '1.614';
    requires 'Parallel::ForkManager';
    requires 'POSIX::AtFork';
    requires 'Scalar::Util';
    requires 'Test::SharedFork';
};
