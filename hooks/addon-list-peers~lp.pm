package Genesis::Hook::Addon::Jumpbox::ListPeers v3.0.0;

use v5.20;
use warnings; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook::Addon);
use Genesis qw/bail info/;

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
	"List WireGuard peers registered in the vault registry.\n".
	"Usage: genesis do <env> -- list-peers\n".
	"This addon requires the 'wireguard' feature to be enabled.\n";
}

sub perform {
	my ($self) = @_;

	$self->require_wireguard();

	my @names = $self->_wg_list_peers;
	if (!@names) {
		info("No peers registered. Add one with:");
		info("  #G{genesis do $ENV{GENESIS_ENVIRONMENT} -- add-peer <name>}");
		return $self->done();
	}

	info("");
	info("Registered WireGuard peers:");
	for my $name (@names) {
		my $address = $self->_wg_peer_get($name, 'address')     || '?';
		my $allowed = $self->_wg_peer_get($name, 'allowed_ips') || '?';
		my $created = $self->_wg_peer_get($name, 'created');
		my $when = $created
			? do {
					my @t = gmtime($created);
					sprintf('%04d-%02d-%02d', $t[5]+1900, $t[4]+1, $t[3]);
				}
			: '?';
		info("  #C{%-24s} %-16s %-10s %s", $name, $address, $when, $allowed);
	}
	info("");
	info("(%d peer%s)", scalar(@names), @names == 1 ? '' : 's');

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
