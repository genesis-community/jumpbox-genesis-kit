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

# _wg_keypair - generate (private, public) base64 Curve25519 pair {{{
sub _wg_keypair {
	my ($self) = @_;

	my ($priv, $rc) = run({stderr => 0}, 'wg genkey 2>/dev/null');
	$priv = defined($priv) ? $priv : ''; chomp($priv);
	if (!$rc && $priv) {
		my ($pub, $prc) = run({stderr => 0}, 'printf \'%s\' "$1" | wg pubkey', $priv);
		$pub = defined($pub) ? $pub : ''; chomp($pub);
		return ($priv, $pub) if !$prc && $pub;
	}

	# openssl X25519 fallback: raw 32-byte keys live at the tail of the
	# PKCS#8 / SPKI DER encodings.
	($priv, $rc) = run({stderr => 0},
		'openssl genpkey -algorithm X25519 -outform DER 2>/dev/null | tail -c 32 | base64');
	$priv = defined($priv) ? $priv : ''; chomp($priv);
	bail("Cannot generate a WireGuard keypair: neither wg nor openssl X25519 available")
		if $rc || !$priv;

	my ($pub, $prc) = run({stderr => 0},
		'{ printf \'\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x6e\x04\x22\x04\x20\'; '.
		'printf \'%s\' "$1" | base64 -d; } | openssl pkey -inform DER -pubout -outform DER 2>/dev/null '.
		'| tail -c 32 | base64', $priv);
	$pub = defined($pub) ? $pub : ''; chomp($pub);
	bail("Cannot derive WireGuard public key via openssl") if $prc || !$pub;

	return ($priv, $pub);
}
# }}}

# _wg_genpsk - generate a base64 preshared key {{{
sub _wg_genpsk {
	my ($self) = @_;
	my ($psk, $rc) = run({stderr => 0}, 'wg genpsk 2>/dev/null');
	$psk = defined($psk) ? $psk : ''; chomp($psk);
	return $psk if !$rc && $psk;

	($psk, $rc) = run({stderr => 0}, 'head -c 32 /dev/urandom | base64');
	$psk = defined($psk) ? $psk : ''; chomp($psk);
	bail("Cannot generate a preshared key") if $rc || !$psk;
	return $psk;
}
# }}}

# _ensure_server_keys - idempotently create the server keypair in vault {{{
sub _ensure_server_keys {
	my ($self) = @_;
	my $path = $self->_wg_server_path;

	my (undef, $rc) = run({stderr => 0},
		'safe --quiet exists "$1:private" && safe --quiet exists "$1:public"', $path);
	return 1 if $rc == 0;

	my ($priv, $pub) = $self->_wg_keypair;
	my (undef, $set_rc) = run({stderr => 0},
		'safe set "$1" "private=$2" "public=$3"',
		$path, $priv, $pub);
	bail("Failed to store WireGuard server keypair at %s", $path) if $set_rc;
	return 1;
}
# }}}

# _wg_list_peers - names registered under the peer registry {{{
sub _wg_list_peers {
	my ($self) = @_;
	my $base = $self->_wg_peers_base;
	my ($out, $rc, $err) = run({stderr => 0}, 'safe paths "$1"', $base);
	if ($rc) {
		# An empty registry reads as "no secret exists" — only complain
		# about other failures (unreachable vault, auth, ...).
		warning(
			"wireguard peer registry lookup failed (safe paths %s): %s",
			$base, $err || 'no output'
		) unless ($err || '') =~ /no secret exists/;
		return ();
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

# _wg_peer_get - fetch one key of a registered peer {{{
sub _wg_peer_get {
	my ($self, $name, $key) = @_;
	my ($out, $rc) = run({stderr => 0},
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
		or bail("Invalid wireguard_cidr '%s' — expected a.b.c.d/nn", $cidr);
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
