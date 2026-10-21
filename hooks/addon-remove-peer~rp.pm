package Genesis::Hook::Addon::Jumpbox::RemovePeer v3.0.0;

use v5.20;
use warnings; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook::Addon);
use Genesis qw/bail info run warning/;

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
	"Usage: genesis <env> do remove-peer <name>\n".
	"This addon requires the 'wireguard' feature to be enabled.\n";
}

sub perform {
	my ($self) = @_;

	$self->require_wireguard();

	my @args = @{$self->{args}};
	bail("USAGE: genesis <env> do remove-peer <name>")
		unless @args == 1;

	my ($name) = @args;
	my $peer_path = $self->_wg_peers_base . $name;

	# Any entry with data moves to the archive, even one that has lost its
	# public key, so that removing a peer never destroys data that was not
	# archived first.
	return $self->_clean_empty_entry($name, $peer_path)
		unless $self->_vault_has($peer_path);

	my $revoked_path = $self->_wg_revoked_base . $name . '-' . time();
	my (undef, $rc) = run({stderr => 0},
		'safe mv "$1" "$2"', $peer_path, $revoked_path);
	bail("Failed to move peer '%s' to %s", $name, $revoked_path) if $rc;
	# On a KV v2 mount the move only marks the source deleted, and its path
	# stays listed with no data.  Destroying every version clears it, and on
	# KV v1 the source is already gone.  The peer is already revoked by now,
	# so a failure here only warns.
	my ($del_rc, $del_err) = $self->_wg_destroy_entry($peer_path);
	warning(
		"Peer '%s' moved to %s, but its registry entry could not be destroyed ".
		"(safe exited %d: %s).  The entry may still hold a soft-deleted version ".
		"that an undelete could restore.  Destroy it by hand with:\n".
		"  safe delete --force --destroy --all %s",
		$name, $revoked_path, $del_rc, $del_err || 'no error output', $peer_path
	) if $del_rc;

	info("");
	info("Peer #C{%s} moved to #Y{%s}", $name, $revoked_path);
	info("");
	info("Revocation takes effect on the next deploy:");
	info("  #G{genesis deploy $ENV{GENESIS_ENVIRONMENT}}");

	return $self->done();
}

# _clean_empty_entry - destroy a listed registry entry that holds no data {{{
# An older remove-peer moved peers away without destroying their entries, so
# on a KV v2 mount the name stays listed with no data.  Such an entry is
# destroyed here; a name that is not listed at all is not registered.
sub _clean_empty_entry {
	my ($self, $name, $peer_path) = @_;
	bail("Peer '%s' is not registered", $name)
		unless grep {$_ eq $name} $self->_wg_registry_names;

	my ($rc, $err) = $self->_wg_destroy_entry($peer_path);
	bail(
		"Peer '%s' has an empty registry entry left by an older remove-peer, ".
		"but it could not be destroyed (safe exited %d: %s).  Destroy it by ".
		"hand with:\n  safe delete --force --destroy --all %s",
		$name, $rc, $err || 'no error output', $peer_path
	) if $rc;

	info("");
	info("Peer #C{%s} had no data, only an empty registry entry that an older", $name);
	info("remove-peer left behind.  That entry is now destroyed, so the peer is");
	info("no longer listed.");
	return $self->done();
}
# }}}

sub require_wireguard {
	my ($self) = @_;
	if (!$self->env->has_feature('wireguard')) {
		bail("This addon requires the 'wireguard' feature to be activated in the $ENV{GENESIS_ENVIRONMENT} environment.");
	}
	return 1;
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
