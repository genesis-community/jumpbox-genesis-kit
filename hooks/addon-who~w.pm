package Genesis::Hook::Addon::Jumpbox::Who v3.0.0;

use v5.20;
use warnings; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'./.genesis/lib'}

use parent qw(Genesis::Hook::Addon);
use Genesis qw/run/;

# Include _get_jumpbox_ip method from mixin
BEGIN {
	require File::Basename;
	my $mixin_file = File::Basename::dirname(__FILE__) . '/lib/_get_jumpbox_ip.pm';
	do $mixin_file or die "Failed to include addon mixin $mixin_file: $!";
}
sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0-rc.20');
	return $obj;
}

sub cmd_details {
	return
		"See who is logged into the jumpbox, via SSH.\n".
		"Logs in as the first account in params.users unless GENESIS_JUMPBOX_USER is set.\n".
	"Any additional arguments will be passed to the ssh command.\n".
		"This requires the ability to login via SSH.\n";
}

sub perform {
	my ($self) = @_;
	my $target = $self->_get_jumpbox_login();
	exec('ssh', $target, @{$self->{args}}, '--', 'who') or bail("Failed to execute SSH command: $!");
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
