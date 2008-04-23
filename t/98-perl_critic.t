
use Test::More;
eval {
	use Test::Perl::Critic ( -exclude => ['ProhibitNoStrict'] );
};
plan skip_all => 'Test::Perl::Critic required to criticise code' if $@;
all_critic_ok();

