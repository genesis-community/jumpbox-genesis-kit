package Genesis::Hook::Addon::Jumpbox::GenerateVpnConfig v3.0.0;

use v5.20;
use warnings; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'./.genesis/lib'}

use parent qw(Genesis::Hook::Addon);
use Genesis qw/run bail/;

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
	"Generate a client certificate (if missing) and an openvpn config file for a given user.\n".
	"Usage: genesis do <env> -- generate-vpn-config [-f] user\@email.addr.ess\n".
	"Options:\n".
	"  -f  Force regeneration of the certificate even if it already exists\n".
	"This addon requires the 'openvpn' feature to be enabled.\n";
}

sub perform {
	my ($self) = @_;

	# Check if openvpn feature is enabled
	$self->require_vpn();

	# Parse arguments
	my @args = @{$self->{args}};
	if (scalar(@args) == 0 || (scalar(@args) == 1 && $args[0] eq '-f')) {
		bail("USAGE: genesis do <env> generate-vpn-config [-f] user\@email.addr.ess");
	}

	my $regen = '';
	if ($args[0] eq '-f') {
		$regen = '1';
		shift @args;
	}

	my $email = $args[0];

	# Get jumpbox IP addresses
	my $ip = $self->_get_jumpbox_ip();

	# Check if the certificate exists, generate if needed
	my ($exists, $exists_rc) = run(
		{quiet => 1},
		'safe --quiet check "$1openvpn/certs/users/$2"',
		$ENV{GENESIS_SECRETS_BASE}, $email
	);

	if ($exists_rc != 0 || $regen) {
		print STDERR "Generating new openvpn client certificate for $email\n";
		$self->issue_cert($email);
	}

	# Get VPN external IP and port
	my $vpn_external_ip = $self->env->lookup('params.vpn_external_ip', $ip);
	if (!$vpn_external_ip) {
		bail("Failed to get VPN External IP from BOSH or Params - check your connection to BOSH or params file");
	}

	my $vpn_protocol = $self->env->lookup('params.vpn_protocol', 'tcp');
	my $vpn_external_port = $self->env->lookup('params.vpn_external_port', '443');
	my $vpn_compress = $self->env->lookup('params.vpn_compress', 'lz4-v2');

	# Get extra client configs
	my $extra_configs = $self->env->lookup('params.vpn_extra_client_configs', []);
	my $extra_config_lines = '';
	if (ref($extra_configs) eq 'ARRAY') {
		$extra_config_lines = join("\n", @$extra_configs);
	}

	# Generate config
	my $ca_cert = $self->vault->get("$ENV{GENESIS_SECRETS_BASE}openvpn/certs/ca:certificate");
	my $client_cert = $self->vault->get("$ENV{GENESIS_SECRETS_BASE}openvpn/certs/users/$email:certificate");
	my $client_key = $self->vault->get("$ENV{GENESIS_SECRETS_BASE}openvpn/certs/users/$email:key");

	print <<EOF;
client
dev tun
proto $vpn_protocol
remote $vpn_external_ip $vpn_external_port
resolv-retry infinite
nobind
persist-key
persist-tun
mute-replay-warnings
remote-cert-tls server
verb 3
mute 20
tls-client
cipher AES-256-CBC
compress $vpn_compress
$extra_config_lines
<ca>
$ca_cert
</ca>
<cert>
$client_cert
</cert>
<key>
$client_key
</key>
EOF

	return $self->done();
}

sub issue_cert {
	my ($self, $email) = @_;

	my $secret = "$ENV{GENESIS_SECRETS_BASE}openvpn/certs/users/$email";
	my $ca = "$ENV{GENESIS_SECRETS_BASE}openvpn/certs/ca";
	my $ttl = $ENV{CERT_TTL} || "180d";

	run('safe x509 issue --signed-by "$1" --name "$2" -u digital_signature -u key_encipherment -u client_auth --ttl "$3" "$4"',
		$ca, $email, $ttl, $secret);

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
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
