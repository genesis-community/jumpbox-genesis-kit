#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker
package Genesis::Hook::PostDeploy::Jumpbox v2.7.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook::PostDeploy);

use Genesis qw/info run/;

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	return $obj;
}

sub perform {
	my ($self) = @_;

	if ($self->deploy_successful) {
		# Get jumpbox IP addresses
		my ($ips_json, $rc, $err) = run('bosh vms --json | jq -r \'.Tables[0].Rows[0].ips\'');
		chomp($ips_json);
		my @ips = split(/\s+/, $ips_json);

		info(
      "#M{$ENV{GENESIS_ENVIRONMENT}} Jumpbox deployed!".
      "For details about the deployment, run\n".
      "  #G{$ENV{GENESIS_CALL_ENV} info}\n".
      "To access the jumpbox over SSH:\n".
      "  #G{$ENV{GENESIS_CALL_ENV} do -- ssh}\n".
      "or:\n".
      "  #W{ssh $ips[0]}\n"
		);
	}

	return $self->done();
}

1;
