#!/usr/bin/env perl
#
# Loads the WireGuard peer registry helpers against a stand-in for the Genesis
# library and prints what they report, so that the spec suite can check the
# registry logic without a live vault. The `safe` command comes from PATH, so
# the caller points PATH at spec/support and sets FAKE_SAFE_DIR.
#
# usage: wireguard-peers.pl <list|fragment>

use strict;
use warnings;
use File::Basename;
use File::Spec;

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
		my $out = qx{bash -c \Q$cmd\E bash @{[ join ' ', map { quotemeta } @args ]} 2>/dev/null};
		return ($out, $? >> 8, '');
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
my $mode = shift @ARGV or die "usage: wireguard-peers.pl <list|fragment>\n";

if ($mode eq 'list') {
	print "$_\n" for Registry->_wg_list_peers;
} elsif ($mode eq 'fragment') {
	my $yaml = Registry->_render_peers_fragment;
	print defined($yaml) ? $yaml : "(none)\n";
} else {
	die "unknown mode '$mode'\n";
}
