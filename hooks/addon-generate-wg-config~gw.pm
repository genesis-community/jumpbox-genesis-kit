package Genesis::Hook::Addon::Jumpbox::GenerateWgConfig v3.0.0;

use v5.20;
use warnings; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook::Addon);
use Genesis qw/bail info run read_json_from/;

# Include WireGuard key/peer helpers and jumpbox IP lookup from mixins
BEGIN {
	require File::Basename;
	for my $mixin (qw(_wireguard_keys.pm _get_jumpbox_ip.pm)) {
		my $mixin_file = File::Basename::dirname(__FILE__) . "/lib/$mixin";
		do $mixin_file or die "Failed to include addon mixin $mixin_file: $!";
	}
}

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0');
	return $obj;
}

sub cmd_details {
	return
	"Emit a wg-quick client configuration for a registered peer.\n".
	"Usage: genesis do <env> -- generate-wg-config [-q] <name>\n".
	"Options:\n".
	"  -q  Also render the config as a terminal QR code (requires qrencode)\n".
	"The endpoint comes from params.wireguard_endpoint, falling back to\n".
	"the deployed jumpbox VM's IP.\n".
	"This addon requires the 'wireguard' feature to be enabled.\n";
}

sub perform {
	my ($self) = @_;

	$self->require_wireguard();

	my %opts = $self->parse_options([ 'qr|q' ]);
	my @args = @{$self->{args}};
	bail("USAGE: genesis do <env> -- generate-wg-config [-q] <name>")
		unless @args == 1;
	my ($name) = @args;

	my $peer_path = $self->_wg_peers_base . $name;
	my (undef, $exists_rc) = run({stderr => 0},
		'safe --quiet exists "$1"', $peer_path);
	bail(
		"Peer '%s' is not registered. Add it with:\n".
		"  genesis do %s -- add-peer %s",
		$name, $ENV{GENESIS_ENVIRONMENT}, $name
	) if $exists_rc != 0;

	my $priv    = $self->_wg_peer_get($name, 'private')
		or bail("Peer '%s' has no private key in vault", $name);
	my $psk     = $self->_wg_peer_get($name, 'psk');
	my $address = $self->_wg_peer_get($name, 'address')
		or bail("Peer '%s' has no address in vault", $name);

	my ($server_pub, $pub_rc) = run({stderr => 0},
		'safe get "$1:public"', $self->_wg_server_path);
	bail("Server public key not found at %s", $self->_wg_server_path) if $pub_rc;
	chomp($server_pub);

	# Endpoint: params -> jumpbox VM IP
	my $port = $self->env->lookup('params.wireguard_port', '51820');
	my $endpoint = $self->env->lookup('params.wireguard_endpoint', '');
	$endpoint ||= $self->_get_jumpbox_ip();
	bail("Cannot determine the WireGuard endpoint — set params.wireguard_endpoint")
		unless $endpoint;
	$endpoint .= ":$port" unless $endpoint =~ /:\d+$/;

	# Client-side routes: the tunnel network plus any routed networks.
	my $cidr = $self->env->lookup('params.wireguard_cidr', '10.20.31.0/24');
	my $routed = $self->env->lookup('params.wireguard_routed_networks', []);
	my @allowed = ($cidr, (ref $routed eq 'ARRAY' ? @$routed : ()));

	my $dns = $self->env->lookup('params.wireguard_dns', []);
	my @dns = ref $dns eq 'ARRAY' ? @$dns : ($dns);

	my $config = "[Interface]\n";
	$config .= "PrivateKey = $priv\n";
	$config .= "Address = $address/32\n";
	$config .= "DNS = " . join(', ', @dns) . "\n" if @dns;
	$config .= "\n[Peer]\n";
	$config .= "PublicKey = $server_pub\n";
	$config .= "PresharedKey = $psk\n" if $psk;
	$config .= "Endpoint = $endpoint\n";
	$config .= "AllowedIPs = " . join(', ', @allowed) . "\n";
	$config .= "PersistentKeepalive = 25\n";

	print $config;

	if ($opts{qr}) {
		my (undef, $qr_missing) = run({stderr => 0}, 'command -v qrencode');
		bail("qrencode not found in PATH — install it for -q output") if $qr_missing;
		run({interactive => 1}, 'printf \'%s\' "$1" | qrencode -t ansiutf8', $config);
	}

	return $self->done();
}

sub require_wireguard {
	my ($self) = @_;
	if (!$self->env->has_feature('wireguard')) {
		bail("This addon requires the 'wireguard' feature to be activated in the $ENV{GENESIS_ENVIRONMENT} environment.");
	}
	return 1;
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
