#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker
package Genesis::Hook::CloudConfig::Jumpbox v2.7.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook::CloudConfig);

use Genesis::Hook::CloudConfig::Helpers qw/gigabytes megabytes/;

use Genesis qw//;
use JSON::PP;

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0-rc.20');
	return $obj;
}

sub perform {
	my ($self) = @_;
	return 1 if $self->completed;

	my $config = $self->build_cloud_config({
		'networks' => [
			$self->network_definition('jumpbox', strategy => 'manual',
				dynamic_subnets => {
					allocation => {
						size => 0,
						statics => 1,
					},
					cloud_properties_for_iaas => {
						openstack => {
							'net_id' => $self->network_reference('id'),
							'security_groups' => ['default']
						},
						stackit => {
							'net_id' => $self->network_reference('id'),
							'security_groups' => ['default']
						},
					},
				},
			)
		],
		'vm_types' => [
			$self->vm_type_definition('jumpbox',
				cloud_properties_for_iaas => {
					openstack => {
						'instance_type' => $self->for_scale({
							small => 'm1.small',
							medium => 'm1.medium',
							large => 'm1.large'
						}, 'm1.small'),
						'boot_from_volume' => $self->TRUE,
						'root_disk' => {
							'size' => 20 # in gigabytes
						},
					},
					stackit => {
						'instance_type' => $self->for_scale({
							small => 'm1.small',
							medium => 'm1.medium',
							large => 'm1.large'
						}, 'm1.small'),
						'boot_from_volume' => $self->TRUE,
						'root_disk' => {
							'size' => 20 # in gigabytes
						},
					},
				},
			),
		],
		'disk_types' => [
			$self->disk_type_definition('jumpbox',
				common => {
					disk_size => $self->for_scale({
						small => gigabytes(32),
						medium => gigabytes(64),
						large => gigabytes(128)
					}, gigabytes(32)),
				},
				cloud_properties_for_iaas => {
					openstack => {
						'type' => 'storage_standard',
					},
					stackit => {
						'type' => 'storage_standard',
					},
				},
			),
		],
	});

	$self->done($config);
}

1;