
use Test::More;
eval {
    require Test::Perl::Critic;
    Test::Perl::Critic->import( -exclude => ['ProhibitNoStrict'] );
};
plan skip_all => 'Test::Perl::Critic required to criticise code' if $@;
all_critic_ok();

