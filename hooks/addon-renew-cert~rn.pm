package Genesis::Hook::Addon::Jumpbox::RenewCert;

use v5.20;
use warnings; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'./.genesis/lib'}

use parent qw(Genesis::Hook::Addon);
use Genesis qw/run bail/;

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0-rc.20');
	return $obj;
}

sub cmd_details {
	return
	"Renew the lifetime of a previously-issued VPN certificate for the specified user, without replacing the key.\n".
	"Usage: genesis do <env> -- renew-cert user@email.addr.ess\n".
	"This addon requires the 'openvpn' feature to be enabled.\n";
}

sub perform {
	my ($self) = @_;

	# Check if openvpn feature is enabled
	$self->require_vpn();

	# Get email from arguments
	my $email = $self->{args}[0];
	if (!$email) {
		bail("USAGE: genesis do <env> -- renew-cert user@email.addr.ess");
	}

	my $secret = "$ENV{GENESIS_SECRETS_BASE}openvpn/certs/users/$email";
	my $ca = "$ENV{GENESIS_SECRETS_BASE}openvpn/certs/ca";

	# Renew certificate
	run('safe x509 renew --signed-by "$1" "$2"', $ca, $secret);
	run('safe x509 show "$1"', $secret);

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
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
