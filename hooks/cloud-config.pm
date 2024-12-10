package Genesis::Hook::CloudConfig::Jumpbox v3.2.0;

use strict;
use warnings;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}
use parent qw(Genesis::Hook::CloudConfig);

use Genesis::Hook::CloudConfig::Helpers qw/gigabytes megabytes/;

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0-rc.4');
	return $obj;
}

sub perform {
	my ($self) = @_;
	return 1 if $self->completed;

	my $config = $self->build_cloud_config({
		'networks' => [
			$self->network_definition('jumpbox', strategy => 'ocfp',
				dynamic_subnets => {
					allocation => {
						size => 0,
						statics => 0,
					},
					cloud_properties_for_iaas => {
						openstack => {
							'net_id' => $self->network_reference('id'), # TODO: $self->subnet_reference('net_id'),
							'security_groups' => ['default'] #$self->subnet_reference('sgs', 'get_security_groups'),
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
							dev => 'g1.1',
							prod => 'g1.2'
						}),
						'boot_from_volume' => $self->TRUE,
						'root_disk' => {'size' => 15}, # in gigabytes
            'ephemeral_disk' => {encrypted => $self->TRUE}
					},
				},
			),
		],
		'disk_types' => [
			$self->disk_type_definition('jumpbox',
				common => {
					disk_size => $self->for_scale({
						dev => gigabytes(48),
						prod => gigabytes(96)
					}),
				},
				cloud_properties_for_iaas => {
					openstack => {
						'type' => $self->for_scale({
              dev  => 'storage_premium_perf6',
              prod => 'storage_premium_perf2'
            })
					},
				},
			),
		],
	});

	$self->done($config);
}

1;
