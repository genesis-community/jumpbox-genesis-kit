#!/usr/bin/env perl
#
# Prints the remote command that the jumpbox who addon builds for the given
# who command line, so that the spec suite can run it under a shell with stub
# commands. The addon is loaded against a stand-in for the Genesis library.
#
# usage: who-script.pl <who command line>

use strict;
use warnings;
use File::Basename;
use File::Spec;

BEGIN {
	package Genesis;
	$INC{'Genesis.pm'} = __FILE__;
	use Exporter 'import';
	our @EXPORT_OK = qw(run bail read_json_from);
	sub bail { die sprintf(shift, @_) . "\n" }
	sub read_json_from { return ({}, 1) }
	sub run { return ('', 0, '') }

	package Genesis::Hook::Addon;
	$INC{'Genesis/Hook/Addon.pm'} = __FILE__;
}

my $hooks = File::Spec->rel2abs(File::Basename::dirname(__FILE__) . '/../../hooks');
do "$hooks/addon-who~w.pm" or die "Failed to load the who addon: " . ($@ || $! || 'unknown error');

my $who = shift @ARGV // 'who';
print bless({}, 'Genesis::Hook::Addon::Jumpbox::Who')->_who_with_fallback($who), "\n";
