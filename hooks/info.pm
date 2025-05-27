#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker
package Genesis::Hook::Info::Jumpbox v2.7.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook);

use Genesis qw/info run/;

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0-rc.20');
	return $obj;
}

sub perform {
	my ($self) = @_;

	# Get jumpbox IP addresses
	my ($ips_json, $rc, $err) = run('bosh vms --json | jq -r \'.Tables[0].Rows[0].ips\'');
	chomp($ips_json);

	my @ips = split(/\s+/, $ips_json);

	info("jumpbox ip(s): #C{" . join(', ', @ips) . "}");

	# TODO: List users and expiry of certs for openvpn users

	return $self->done();
}

1;
