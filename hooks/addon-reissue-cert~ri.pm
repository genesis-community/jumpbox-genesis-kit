#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker
package Genesis::Hook::Addon::Jumpbox::ReissueCert v2.7.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20

use parent qw(Genesis::Hook::Addon);
use lib $ENV{GENESIS_LIB} // "$ENV{HOME}/.genesis/lib";

use Genesis qw/run bail/;

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0-rc.20');
	return $obj;
}

sub cmd_details {
	return
	"Re-issue a VPN user certificate, regenerating the user's key. The old certificate will be revoked.\n".
	"Usage: genesis do <env> -- reissue-cert user@email.addr.ess\n".
	"This addon requires the 'openvpn' feature to be enabled.\n";
}

sub perform {
	my ($self) = @_;

	# Check if openvpn feature is enabled
	$self->require_vpn();

	# Get email from arguments
	my $email = $self->{args}[0];
	if (!$email) {
		bail("USAGE: genesis do <env> -- reissue-cert user@email.addr.ess");
	}

	my $secret = "$ENV{GENESIS_SECRETS_BASE}openvpn/certs/users/$email";
	my $ca = "$ENV{GENESIS_SECRETS_BASE}openvpn/certs/ca";

  # TODO: Check for error case and handle it
	# Reissue certificate
	run('safe x509 reissue --signed-by "$1" "$2"', $ca, $secret);
	run('safe x509 show "$1"', $secret);

	return 1;
}

sub require_vpn {
	my ($self) = @_;
	if (!$self->env->has_feature('openvpn')) {
		bail("This addon requires the 'openvpn' feature to be activated in the $ENV{GENESIS_ENVIRONMENT} environment.");
	}
	return 1;
}

1;
