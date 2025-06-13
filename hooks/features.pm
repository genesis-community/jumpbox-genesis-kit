#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker
package Genesis::Hook::Features::Jumpbox v2.7.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20

use parent qw(Genesis::Hook::Features);
use lib $ENV{GENESIS_LIB} // "$ENV{HOME}/.genesis/lib";

use Genesis qw/bail/;

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0-rc.20');
	return $obj;
}

sub perform {
	my ($self) = @_;

	# Process requested features
	foreach my $feature (@{$self->{features}}) {
		if ($feature eq 'openvpn' || $feature eq 'bastion' || $feature eq 'dev-tools') {
			$self->add_feature($feature);
		}
		elsif ($feature eq 'shield') {
			bail(
				"The Jumpbox Genesis Kit no longer supplies a 'shield' feature flag.\n".
				"If you wish to back up this jumpbox, please switch to using BOSH\n".
				"runtime configurations to add the shield-agent to the deployment."
			);
		}
		elsif ($feature eq 'azure') {
			# Ignore azure feature - it's defunct
			# Don't add but don't bail either
		}
		elsif ($feature eq 'proxy') {
			# Proxy is implicit, no need to add it
		}
		elsif (-f $self->env->path("ops/$feature.yml")) {
			$self->add_feature($feature);
		}
		else {
			bail(
				"Feature [$feature] not supported in this context.\n".
				"Supported features are: openvpn, bastion, dev-tools, and custom ops files."
			);
		}
	}

	return $self->done();
}

1;
