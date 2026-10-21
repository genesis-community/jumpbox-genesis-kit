# Shared WireGuard key/peer helpers, included into hook packages via:
#   do <hooks-dir>/lib/_wireguard_keys.pm
#
# WireGuard uses base64 Curve25519 keypairs, which the Genesis
# credentials DSL cannot generate — so key lifecycle lives here:
#   server keypair   <secrets-base>server:{private,public}
#   peer registry    <secrets-base>peers/<name>:{private,public,psk,
#                      address,allowed_ips,created}
#   revoked peers    <secrets-base>revoked/<name>-<epoch>
#
# Key generation prefers `wg`; falls back to openssl X25519 (raw key
# extracted from PKCS#8 DER) so hooks work without wireguard-tools.

use Genesis qw/bail run warning/;
use File::Temp qw/tempdir/;

BEGIN {
	require File::Basename;
	my $mixin_file = File::Basename::dirname(__FILE__) . '/_vault_exists.pm';
	do $mixin_file or die "Failed to include $mixin_file: " . ($@ || $! || 'unknown error');
}

# Relative prefix under GENESIS_SECRETS_BASE for wireguard secrets.
# 'wireguard/' here: the jumpbox kit namespaces its wireguard secrets
# alongside openvpn/ (the standalone wireguard kit uses '').
sub _wg_secrets_prefix { 'wireguard/' }

# GENESIS_SECRETS_BASE may carry a leading slash; safe emits paths
# without one, so normalize it away for consistent matching.
sub _wg_base {
	my $base = $ENV{GENESIS_SECRETS_BASE} . $_[0]->_wg_secrets_prefix;
	$base =~ s{^/}{};
	return $base;
}
sub _wg_server_path { $_[0]->_wg_base . 'server' }
sub _wg_peers_base  { $_[0]->_wg_base . 'peers/' }
sub _wg_revoked_base{ $_[0]->_wg_base . 'revoked/' }

# _wg_secret_file - write a secret to a private temporary file {{{
# Keys are handed to wg, openssl, and safe through files, because a command
# line argument is readable by every local user for as long as the process
# runs.  The directory is created 0700 and removed when the hook exits.
# safe reads a `key=value` argument before it looks for `key@file`, so a path
# holding `=` would be stored as a literal value, and such a path is refused.
my $_wg_tmpdir;
sub _wg_secret_file {
	my ($self, $name, $value) = @_;
	$_wg_tmpdir //= tempdir('wireguard-keys-XXXXXX', TMPDIR => 1, CLEANUP => 1);
	my $file = "$_wg_tmpdir/$name";
	bail(
		"Cannot hand a key to safe through %s, because safe reads a path that ".
		"contains '=' as a literal value.  Set TMPDIR to a directory without '='.",
		$file
	) if $file =~ /=/;
	my $old = umask(077);
	my $ok = open(my $fh, '>', $file);
	umask($old);
	bail("Cannot write a temporary key file in %s: %s", $_wg_tmpdir, $!) unless $ok;
	print $fh $value;
	close($fh) or bail("Cannot write a temporary key file in %s: %s", $_wg_tmpdir, $!);
	return $file;
}
# }}}

# _wg_safe_set - store fields at a vault path, secrets through files {{{
# Takes the path, a hash of fields, and the names of the fields that are
# secret.  Secret fields reach safe with its key@file form, so their values
# never appear on a command line.
sub _wg_safe_set {
	my ($self, $path, $fields, @secret) = @_;
	my %secret = map {$_ => 1} @secret;
	my @args = map {
		$secret{$_} ? "$_\@".$self->_wg_secret_file("set-$_", $fields->{$_}) : "$_=$fields->{$_}"
	} sort keys %$fields;
	my (undef, $rc) = run({stderr => 0}, 'safe set "$@"', $path, @args);
	unlink(map {"$_wg_tmpdir/set-$_"} grep {$secret{$_}} keys %$fields) if $_wg_tmpdir;
	return $rc;
}
# }}}

# _wg_keypair - generate (private, public) base64 Curve25519 pair {{{
# The private key is redacted from the trace log, and the file that hands it
# to the public key derivation is removed as soon as the derivation returns.
sub _wg_keypair {
	my ($self) = @_;

	my ($priv, $rc) = run({stderr => 0, redact_output => 1}, 'wg genkey 2>/dev/null');
	$priv = defined($priv) ? $priv : ''; chomp($priv);
	if (!$rc && $priv) {
		my $key_file = $self->_wg_secret_file('genkey', $priv);
		my ($pub, $prc) = run({stderr => 0}, 'wg pubkey < "$1"', $key_file);
		unlink($key_file);
		$pub = defined($pub) ? $pub : ''; chomp($pub);
		return ($priv, $pub) if !$prc && $pub;
	}

	# openssl X25519 fallback: raw 32-byte keys live at the tail of the
	# PKCS#8 / SPKI DER encodings.
	($priv, $rc) = run({stderr => 0, redact_output => 1},
		'openssl genpkey -algorithm X25519 -outform DER 2>/dev/null | tail -c 32 | base64');
	$priv = defined($priv) ? $priv : ''; chomp($priv);
	bail("Cannot generate a WireGuard keypair: neither wg nor openssl X25519 available")
		if $rc || !$priv;

	my $key_file = $self->_wg_secret_file('genpkey', $priv);
	my ($pub, $prc) = run({stderr => 0},
		'{ printf \'\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x6e\x04\x22\x04\x20\'; '.
		'base64 -d < "$1"; } | openssl pkey -inform DER -pubout -outform DER 2>/dev/null '.
		'| tail -c 32 | base64', $key_file);
	unlink($key_file);
	$pub = defined($pub) ? $pub : ''; chomp($pub);
	bail("Cannot derive WireGuard public key via openssl") if $prc || !$pub;

	return ($priv, $pub);
}
# }}}

# _wg_genpsk - generate a base64 preshared key {{{
# Both sources are redacted from the trace log.
sub _wg_genpsk {
	my ($self) = @_;
	my ($psk, $rc) = run({stderr => 0, redact_output => 1}, 'wg genpsk 2>/dev/null');
	$psk = defined($psk) ? $psk : ''; chomp($psk);
	return $psk if !$rc && $psk;

	($psk, $rc) = run({stderr => 0, redact_output => 1}, 'head -c 32 /dev/urandom | base64');
	$psk = defined($psk) ? $psk : ''; chomp($psk);
	bail("Cannot generate a preshared key") if $rc || !$psk;
	return $psk;
}
# }}}

# _ensure_server_keys - idempotently create the server keypair in vault {{{
sub _ensure_server_keys {
	my ($self) = @_;
	my $path = $self->_wg_server_path;

	return 1 if $self->_vault_has("$path:private") && $self->_vault_has("$path:public");

	my ($priv, $pub) = $self->_wg_keypair;
	my $set_rc = $self->_wg_safe_set($path, {private => $priv, public => $pub}, 'private');
	bail("Failed to store WireGuard server keypair at %s", $path) if $set_rc;
	return 1;
}
# }}}

# _wg_registry_names - every name listed under the peer registry {{{
# Includes entries with no data, which a KV v2 mount keeps listing after
# their latest version is deleted.  Use _wg_list_peers for live peers.
sub _wg_registry_names {
	my ($self) = @_;
	my $base = $self->_wg_peers_base;
	my ($out, $rc, $err) = run({stderr => 0}, 'safe paths "$1"', $base);
	if ($rc) {
		# An empty registry reads as "no secret exists".  Any other failure
		# (unreachable vault, auth, ...) must stop the caller, because an
		# empty list would drop every peer from the next deploy.
		my $msg = _wg_clean_err($err);
		return () if $msg =~ /no secret exists/;
		bail(
			"The wireguard peer registry at #C{%s} could not be listed (safe paths exited %d): %s",
			$base, $rc, $msg || 'no output'
		);
	}
	return () if !$out;
	my %seen;
	for my $line (split /\n/, $out) {
		next unless $line =~ /^\Q$base\E(.+)$/;
		$seen{$1} = 1;
	}
	return sort keys %seen;
}
# }}}

# _wg_list_peers - names of registered peers whose public key can be read {{{
# On a KV v2 mount, `safe paths` still lists a secret after it has been
# moved or deleted, because the soft-deleted versions remain. Only a peer
# whose public key can still be read is registered. A vault error stops the
# run, so a peer is never dropped because the vault could not answer.
sub _wg_list_peers {
	my ($self) = @_;
	my $base = $self->_wg_peers_base;
	return grep {
		$self->_vault_has($base . $_ . ':public');
	} $self->_wg_registry_names;
}
# }}}

# _wg_clean_err - safe's error output without colour codes or edge whitespace {{{
# Returns '' for undef, so callers can test for "no error output" directly.
sub _wg_clean_err {
	my ($err) = @_;
	$err = defined($err) ? $err : '';
	$err =~ s/\e\[[0-9;]*m//g;
	$err =~ s/^\s+|\s+$//g;
	return $err;
}
# }}}

# _wg_destroy_entry - destroy every version of a vault path {{{
# Returns safe's exit code and its cleaned error output.  With --force, safe
# treats an absent path as success, so a KV v1 entry that a move already
# removed reports 0.
sub _wg_destroy_entry {
	my ($self, $path) = @_;
	my (undef, $rc, $err) = run({stderr => 0}, 'safe delete --force --destroy --all "$1"', $path);
	return ($rc, _wg_clean_err($err));
}
# }}}

# _wg_peer_get - fetch one key of a registered peer {{{
# The private key and the preshared key are redacted from the trace log.
sub _wg_peer_get {
	my ($self, $name, $key) = @_;
	my ($out, $rc) = run({stderr => 0, redact_output => ($key =~ /^(?:private|psk)$/ ? 1 : 0)},
		'safe get "$1:$2"', $self->_wg_peers_base . $name, $key);
	return undef if $rc;
	$out = defined($out) ? $out : ''; chomp($out);
	return $out;
}
# }}}

# _wg_alloc_address - lowest free host >= .2 in the given CIDR {{{
# .1 is the server by convention.
sub _wg_alloc_address {
	my ($self, $cidr) = @_;
	my ($ip, $bits) = $cidr =~ m{^(\d+\.\d+\.\d+\.\d+)/(\d+)$}
		or bail("Invalid wireguard_cidr '%s', which should look like a.b.c.d/nn", $cidr);
	bail("wireguard_cidr prefix /%s too small for peer allocation", $bits) if $bits > 30;

	my $to_int   = sub { my @o = split /\./, $_[0]; ($o[0]<<24)|($o[1]<<16)|($o[2]<<8)|$o[3] };
	my $to_quad  = sub { join '.', ($_[0]>>24)&255, ($_[0]>>16)&255, ($_[0]>>8)&255, $_[0]&255 };
	my $mask     = $bits == 0 ? 0 : (0xFFFFFFFF << (32 - $bits)) & 0xFFFFFFFF;
	my $network  = $to_int->($ip) & $mask;
	my $broadcast= $network | (~$mask & 0xFFFFFFFF);

	my %taken;
	for my $name ($self->_wg_list_peers) {
		my $addr = $self->_wg_peer_get($name, 'address') or next;
		$taken{$addr} = 1;
	}

	for (my $host = $network + 2; $host < $broadcast; $host++) {
		my $candidate = $to_quad->($host);
		return $candidate unless $taken{$candidate};
	}
	bail("No free addresses left in %s", $cidr);
}
# }}}

# _render_peers_fragment - manifest fragment enumerating vault peers {{{
# Returns undef when the registry is empty so first deploys and spec
# runs stay green. Key material is referenced via (( vault )) ops —
# never rendered literally.
sub _render_peers_fragment {
	my ($self, $ig_name) = @_;
	$ig_name ||= 'wireguard';

	my @names = $self->_wg_list_peers;
	return undef unless @names;

	my $base = $self->_wg_peers_base;
	my $yaml = <<"EOF";
instance_groups:
- name: $ig_name
  jobs:
  - name: wireguard
    properties:
      wireguard:
        peers:
EOF
	for my $name (@names) {
		my $allowed = $self->_wg_peer_get($name, 'allowed_ips');
		bail("Peer '%s' in vault registry is missing allowed_ips", $name)
			unless $allowed;
		my @allowed = grep { length } split /[,\s]+/, $allowed;
		$yaml .= "        - name: $name\n";
		$yaml .= "          public_key: (( vault \"$base$name:public\" ))\n";
		$yaml .= "          preshared_key: (( vault \"$base$name:psk\" ))\n";
		$yaml .= "          allowed_ips:\n";
		$yaml .= "          - $_\n" for @allowed;
	}
	return $yaml;
}
# }}}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
