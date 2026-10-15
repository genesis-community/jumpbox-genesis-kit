#!/usr/bin/env perl
#
# Loads the WireGuard peer registry helpers against a stand-in for the Genesis
# library and prints what they report, so that the spec suite can check the
# registry logic without a live vault. The `safe` command comes from PATH, so
# the caller points PATH at spec/support and sets FAKE_SAFE_DIR.
#
# usage: wireguard-peers.pl <list|fragment|has REF|alloc CIDR>

use strict;
use warnings;
use File::Basename;
use File::Spec;
use File::Temp ();

BEGIN {
	package Genesis;
	$INC{'Genesis.pm'} = __FILE__;
	use Exporter 'import';
	our @EXPORT_OK = qw(bail run warning);

	sub bail { my ($fmt, @a) = @_; die sprintf($fmt, @a) . "\n" }
	sub warning { my ($fmt, @a) = @_; print STDERR sprintf($fmt, @a) . "\n" }
	sub run {
		shift if ref($_[0]) eq 'HASH';
		my ($cmd, @args) = @_;
		my ($efh, $errfile) = File::Temp::tempfile(UNLINK => 0); close $efh;
		my $out = qx{bash -c \Q$cmd\E bash @{[ join ' ', map { quotemeta } @args ]} 2>$errfile};
		my $rc = $? >> 8;
		open my $fh, '<', $errfile; local $/; my $err = <$fh> // ''; close $fh; unlink $errfile;
		return ($out, $rc, $err);
	}
}

package Registry;

BEGIN {
	my $lib = File::Spec->rel2abs(
		File::Basename::dirname(__FILE__) . '/../../hooks/lib/_wireguard_keys.pm'
	);
	do $lib or die "Failed to include $lib: " . ($@ || $! || 'unknown error');
}

package main;

$ENV{GENESIS_SECRETS_BASE} = 'secret/test/jumpbox/';
my $mode = shift @ARGV or die "usage: wireguard-peers.pl <list|fragment|has REF|alloc CIDR>\n";

if ($mode eq 'list') {
	print "$_\n" for Registry->_wg_list_peers;
} elsif ($mode eq 'fragment') {
	my $yaml = Registry->_render_peers_fragment;
	print defined($yaml) ? $yaml : "(none)\n";
} elsif ($mode eq 'has') {
	print Registry->_vault_has(shift @ARGV) ? "yes\n" : "no\n";
} elsif ($mode eq 'alloc') {
	print Registry->_wg_alloc_address(shift @ARGV), "\n";
} else {
	die "unknown mode '$mode'\n";
}
