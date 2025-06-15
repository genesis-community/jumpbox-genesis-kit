# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
package Genesis::Hook::Addon::Jumpbox::RevokeCert;

use v5.20;
use warnings; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'./.genesis/lib'}

use parent qw(Genesis::Hook::Addon);
use Genesis qw/run bail info/;

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0-rc.20');
	return $obj;
}

sub cmd_details {
	return
	"Revokes an issued VPN user certificate, preventing them from accessing the VPN.\n".
	"Usage: genesis do <env> -- revoke-cert user@email.addr.ess\n".
	"This addon requires the 'openvpn' feature to be enabled.\n";
}

sub perform {
	my ($self) = @_;

	# Check if openvpn feature is enabled
	$self->require_vpn();

	# Get email from arguments
	my $email = $self->{args}[0];
	if (!$email) {
		bail("USAGE: genesis do <env> -- revoke-cert user@email.addr.ess");
	}

	my $secret = "$ENV{GENESIS_SECRETS_BASE}openvpn/certs/users/$email";
	my $ca = "$ENV{GENESIS_SECRETS_BASE}openvpn/certs/ca";

	# Check if certificate exists
	my ($exists, $rc) = run({stderr => 0}, 'safe exists "$1"', $secret);
	if ($rc != 0) {
		info("%s does not have a certificate in the Vault\n", $email);
		return 1;
	}

	# Revoke certificate
	run('safe x509 revoke --signed-by "$1" "$2"', $ca, $secret);
	run('safe rm "$1"', $secret);

	info("revoked #Y{%s} VPN user certificate",$email);

	return $self->done();
}

sub require_vpn {
	my ($self) = @_;
	if (!$self->env->has_feature('openvpn')) {
		bail("This addon requires the 'openvpn' feature to be activated in the $ENV{GENESIS_ENVIRONMENT} environment.");
	}
	return 1;
}

1;
