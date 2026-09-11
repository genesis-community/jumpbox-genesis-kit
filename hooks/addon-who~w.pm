package Genesis::Hook::Addon::Jumpbox::Who v3.0.0;

use v5.20;
use warnings; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook::Addon);
use Genesis qw/run/;

# Include the jumpbox login and ssh command helpers from the mixins
BEGIN {
	require File::Basename;
	my $lib = File::Basename::dirname(__FILE__) . '/lib';
	for my $mixin (qw(_get_jumpbox_ip.pm _ssh_command.pm)) {
		my $mixin_file = "$lib/$mixin";
		do $mixin_file or die "Failed to include addon mixin $mixin_file: $!";
	}
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
		"Arguments before a '--' are passed to the ssh command itself, and\n".
		"arguments after a '--' are passed to the remote 'who' command.\n".
		"This requires the ability to login via SSH.\n";
}

sub perform {
	my ($self) = @_;
	my $target = $self->_get_jumpbox_login();
	my @cmd = $self->_ssh_command($target, $self->{args}, 'who');
	exec(@cmd) or bail("Failed to execute SSH command: $!");
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
