package Genesis::Hook::Addon::Jumpbox::AddPeer v3.0.0;

use v5.20;
use warnings; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook::Addon);
use Genesis qw/bail info run/;

# Include WireGuard key/peer helpers from mixin
BEGIN {
	require File::Basename;
	my $mixin_file = File::Basename::dirname(__FILE__) . '/lib/_wireguard_keys.pm';
	do $mixin_file or die "Failed to include addon mixin $mixin_file: $!";
}

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0');
	return $obj;
}

sub cmd_details {
	return
	"Register a new WireGuard peer in the vault registry.\n".
	"Generates a keypair and preshared key, allocates the lowest free\n".
	"tunnel address, and stores everything in vault. The peer becomes\n".
	"active on the next deploy (applied via wg syncconf - no tunnel drop).\n".
	"Usage: genesis <env> do add-peer <name> [extra-allowed-cidr ...]\n".
	"This addon requires the 'wireguard' feature to be enabled.\n";
}

sub perform {
	my ($self) = @_;

	$self->require_wireguard();

	my @args = @{$self->{args}};
	bail("USAGE: genesis <env> do add-peer <name> [extra-allowed-cidr ...]")
		unless @args;

	my ($name, @extra_cidrs) = @args;
	bail("Peer name must match [a-zA-Z0-9._\@-]+, got '%s'", $name)
		unless $name =~ /^[a-zA-Z0-9._\@-]+$/;
	for my $cidr (@extra_cidrs) {
		bail("Invalid extra allowed CIDR '%s'", $cidr)
			unless $cidr =~ m{^\d+\.\d+\.\d+\.\d+/\d+$};
	}

	my $peer_path = $self->_wg_peers_base . $name;
	my (undef, $exists_rc) = run({stderr => 0},
		'safe --quiet exists "$1"', $peer_path);
	bail(
		"Peer '%s' already exists. Remove it first with:\n".
		"  genesis %s do remove-peer %s",
		$name, $ENV{GENESIS_ENVIRONMENT}, $name
	) if $exists_rc == 0;

	my $cidr = $self->env->lookup('params.wireguard_cidr', '10.20.31.0/24');
	my $address = $self->_wg_alloc_address($cidr);
	my ($priv, $pub) = $self->_wg_keypair;
	my $psk = $self->_wg_genpsk;
	my $allowed = join(',', "$address/32", @extra_cidrs);

	my (undef, $rc) = run({stderr => 0},
		'safe set "$1" "private=$2" "public=$3" "psk=$4" "address=$5" "allowed_ips=$6" "created=$7"',
		$peer_path, $priv, $pub, $psk, $address, $allowed, time());
	bail("Failed to store peer '%s' at %s", $name, $peer_path) if $rc;

	info("");
	info("Registered peer #C{%s}", $name);
	info("  address:     %s", $address);
	info("  allowed_ips: %s", $allowed);
	info("  public key:  %s", $pub);
	info("");
	info("Activate the peer with:");
	info("  #G{genesis deploy $ENV{GENESIS_ENVIRONMENT}}");
	info("");
	info("Then emit its client config with:");
	info("  #G{genesis $ENV{GENESIS_ENVIRONMENT} do generate-wg-config %s}", $name);

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
