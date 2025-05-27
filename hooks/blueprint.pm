#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker
package Genesis::Hook::Blueprint::Jumpbox v2.7.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook);

use Genesis qw/bail describe info/;

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0-rc.20');
	$obj->{files} = [];
	return $obj;
}

sub perform {
	my ($self) = @_;

	# Base manifest files
	$self->add_files(
		"manifests/jumpbox.yml",
		"manifests/releases/jumpbox.yml",
		"manifests/releases/toolbelt.yml"
	);

	# Process features
	my @features = $self->env->features;
	foreach my $feature (@features) {
		if ($feature eq 'openvpn') {
			$self->add_files(
				"manifests/addons/openvpn.yml",
				"manifests/releases/openvpn.yml",
				"manifests/releases/networking.yml"
			);
		}
		elsif ($feature eq 'bastion' || $feature eq 'dev-tools') {
			$self->add_files("manifests/$feature.yml");
		}
		elsif ($feature eq 'shield') {
			bail(
				"The Jumpbox Genesis Kit no longer supplies a 'shield' feature flag.\n".
				"If you wish to back up this jumpbox, please switch to using BOSH\n".
				"runtime configurations to add the shield-agent to the deployment."
			);
		}
		elsif ($feature eq 'azure') {
			info(
				"The Jumpbox Genesis Kit no longer supplies a 'azure' feature flag.\n".
				"This is because the 'azure' feature only impacted availability zones\n".
				"and sets, which have no impact on a single-instance deployment."
			);
		}
		elsif ($feature eq 'proxy') {
			info(
				"You no longer need to explicitly specify the 'proxy' feature.\n".
				"If you remove it, everything will still work as expected."
			);
		}
		elsif (-f $self->env->path("ops/$feature.yml")) {
			$self->add_files($self->env->path("ops/$feature.yml"));
		}
		else {
			bail(
				"The #c{$feature} feature is invalid. See the manual for list of valid features."
			);
		}
	}

	# Add users file if specified
	my $users_file = $self->env->lookup('params.users_file', '');
	if ($users_file) {
		$self->add_files("manifests/users.yml");
	}

	return $self->done($self->{files});
}

sub add_files {
	my ($self, @files) = @_;
	push @{$self->{files}}, @files;
}

1;
