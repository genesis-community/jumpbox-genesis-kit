#!/usr/bin/env perl
#
# Prints the argument vector that the jumpbox ssh and who addons build, one
# argument to a line, so that the spec suite can assert on it without a live
# deployment. The first argument is the ssh login target. The second is the
# command word the addon always puts first, which is empty for the ssh addon
# and "who" for the who addon. Everything after those two is what the addon
# received from Genesis.

use strict;
use warnings;
use File::Basename;
use File::Spec;

package Addon;

BEGIN {
	my $mixin = File::Spec->rel2abs(
		File::Basename::dirname(__FILE__) . '/../../hooks/lib/_ssh_command.pm'
	);
	do $mixin or die "Failed to include $mixin: " . ($@ || $! || 'unknown error');
}

package main;

die "usage: ssh-command.pl <target> <prefix> [args...]\n" if @ARGV < 2;

my ($target, $prefix, @args) = @ARGV;
my @prefix = length($prefix) ? ($prefix) : ();

print "$_\n" for Addon->_ssh_command($target, \@args, @prefix);
