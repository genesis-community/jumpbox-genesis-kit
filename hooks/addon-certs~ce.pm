# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
package Genesis::Hook::Addon::Jumpbox::Certs;

use v5.20;
use warnings; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'./.genesis/lib'}

use parent qw(Genesis::Hook::Addon);
use Genesis qw/run info bail/;

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0-rc.20');
	return $obj;
}

sub cmd_details {
	return
	"List the VPN certificates for the users defined on the given jumpbox environment.\n".
	"This addon requires the 'openvpn' feature to be enabled.\n";
}

sub perform {
	my ($self) = @_;

	# Check if openvpn feature is enabled
	$self->require_vpn();

	my $n = 0;
	my ($paths, $rc, $err) = run({stderr => 0},
		'safe paths "$1openvpn/certs/users" 2>/dev/null',
		$ENV{GENESIS_SECRETS_BASE});

	for my $secret (split(/\n/, $paths)) {
		next unless $secret;
		run('safe x509 show "$1"', $secret);
		print "\n\n";
		$n++;
	}

	info "$n VPN user certificates found\n";

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
