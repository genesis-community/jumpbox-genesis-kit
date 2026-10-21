#!/usr/bin/env perl
#
# Runs the perform method of one of the jumpbox WireGuard peer addons against
# a stand-in for the Genesis library, so that the spec suite can check how the
# addon changes the peer registry without a live deployment. The `safe`
# command comes from PATH, so the caller points PATH at spec/support and sets
# FAKE_SAFE_DIR.
#
# usage: wireguard-addon.pl <add-peer|remove-peer|list-peers> [args ...]

use strict;
use warnings;
use File::Basename;
use File::Spec;
use File::Temp ();

BEGIN {
	package Genesis;
	$INC{'Genesis.pm'} = __FILE__;
	use Exporter 'import';
	our @EXPORT_OK = qw(bail run info warning);

	sub bail { my ($fmt, @a) = @_; die sprintf($fmt, @a) . "\n" }
	sub info { my ($fmt, @a) = @_; print sprintf($fmt // '', @a) . "\n" }
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

	package Genesis::Hook::Addon;
	$INC{'Genesis/Hook/Addon.pm'} = __FILE__;
	sub env { $_[0] }
	sub has_feature { 1 }
	sub lookup { $_[2] }
	sub done { 0 }
}

my %addons = (
	'remove-peer' => ['addon-remove-peer~rp.pm', 'Genesis::Hook::Addon::Jumpbox::RemovePeer'],
	'list-peers'  => ['addon-list-peers~lp.pm',  'Genesis::Hook::Addon::Jumpbox::ListPeers'],
	'add-peer'    => ['addon-add-peer~ap.pm',    'Genesis::Hook::Addon::Jumpbox::AddPeer'],
);
my $which = shift @ARGV;
my ($file, $class) = @{$addons{$which // ''} || []}
	or die "usage: wireguard-addon.pl <add-peer|remove-peer|list-peers> [args ...]\n";
$file = File::Spec->rel2abs(File::Basename::dirname(__FILE__) . "/../../hooks/$file");

$ENV{GENESIS_SECRETS_BASE} = 'secret/test/jumpbox/';
$ENV{GENESIS_ENVIRONMENT} = 'test';
do $file or die "Failed to load $file: " . ($@ || $! || 'unknown error');
bless({args => [@ARGV]}, $class)->perform;
