package Genesis::Hook::Addon::Jumpbox::IssueCert v3.0.0;

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
	"Issue a new VPN certificate to a named user, so that they can access the VPN.\n".
	"Usage: genesis <env> do issue-cert user\@email.addr.ess\n".
	"This addon requires the 'openvpn' feature to be enabled.\n";
}

sub perform {
	my ($self) = @_;

	# Check if openvpn feature is enabled
	$self->require_vpn();

	# Get email from arguments
	my $email = $self->{args}[0];
	if (!$email) {
		bail("USAGE: genesis <env> do issue-cert user\@email.addr.ess");
	}

	my $secret = "$ENV{GENESIS_SECRETS_BASE}openvpn/certs/users/$email";
	my $ca = "$ENV{GENESIS_SECRETS_BASE}openvpn/certs/ca";
	my $ttl = $ENV{CERT_TTL} || "180d";

	# Issue certificate
  # TODO: Use Genesis run cmd.
	run('safe x509 issue --signed-by "$1" --name "$2" -u digital_signature -u key_encipherment -u client_auth --ttl "$3" "$4"',
		$ca, $email, $ttl, $secret);

	# Show the newly-issued cert unless --quiet was supplied
	my $quiet = ($self->{args}[1] && $self->{args}[1] eq '--quiet') ? 1 : 0;
	unless ($quiet) {
		run('safe x509 show $1', $secret);
		info(
		"To get the certificate:\n".
		"  #C{safe read %s:certificate}\n".
		"To get the private key:\n".
		"  #Y{safe read %s:key}\n",
		$secret, $secret
		);
	}

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
