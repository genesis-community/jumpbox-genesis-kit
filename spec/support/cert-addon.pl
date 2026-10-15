#!/usr/bin/env perl
#
# Runs the perform method of one of the jumpbox certificate addons against a
# stand-in for the Genesis library, so that the spec suite can check how the
# addon reacts to the vault without a live deployment. The `safe` command
# comes from PATH, so the caller points PATH at spec/support and sets
# FAKE_SAFE_DIR.
#
# usage: cert-addon.pl <certs|renew-all-certs>

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
	sub info { my ($fmt, @a) = @_; print sprintf($fmt, @a) . "\n" }
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
	sub done { 0 }
}

my %files = (
	'certs'           => 'addon-certs~ce.pm',
	'renew-all-certs' => 'addon-renew-all-certs~ra.pm',
);
my $which = shift @ARGV;
my $file = $files{$which // ''} or die "usage: cert-addon.pl <certs|renew-all-certs>\n";
$file = File::Spec->rel2abs(File::Basename::dirname(__FILE__) . "/../../hooks/$file");

$ENV{GENESIS_SECRETS_BASE} = 'secret/test/jumpbox/';
$ENV{GENESIS_ENVIRONMENT} = 'test';
my $pkg = do $file or die "Failed to load $file: " . ($@ || $! || 'unknown error');
my $class = $which eq 'certs'
	? 'Genesis::Hook::Addon::Jumpbox::Certs'
	: 'Genesis::Hook::Addon::Jumpbox::RenewAllCerts';
bless({}, $class)->perform;
