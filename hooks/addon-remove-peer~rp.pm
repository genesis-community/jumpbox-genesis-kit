package Genesis::Hook::Addon::Jumpbox::RemovePeer v3.0.0;

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
	"Revoke a WireGuard peer: its registry entry moves to the revoked/\n".
	"archive and the next deploy drops it from the interface config.\n".
	"Usage: genesis do <env> -- remove-peer <name>\n".
	"This addon requires the 'wireguard' feature to be enabled.\n";
}

sub perform {
	my ($self) = @_;

	$self->require_wireguard();

	my @args = @{$self->{args}};
	bail("USAGE: genesis do <env> -- remove-peer <name>")
		unless @args == 1;

	my ($name) = @args;
	my $peer_path = $self->_wg_peers_base . $name;

	my (undef, $exists_rc) = run({stderr => 0},
		'safe --quiet exists "$1"', $peer_path);
	bail("Peer '%s' is not registered", $name) if $exists_rc != 0;

	my $revoked_path = $self->_wg_revoked_base . $name . '-' . time();
	my (undef, $rc) = run({stderr => 0},
		'safe mv "$1" "$2"', $peer_path, $revoked_path);
	bail("Failed to move peer '%s' to %s", $name, $revoked_path) if $rc;

	info("");
	info("Peer #C{%s} moved to #Y{%s}", $name, $revoked_path);
	info("");
	info("Revocation takes effect on the next deploy:");
	info("  #G{genesis deploy $ENV{GENESIS_ENVIRONMENT}}");

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
