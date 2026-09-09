package Genesis::Hook::CloudConfig::Jumpbox v3.0.0;

use v5.20;
use warnings;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}
use parent qw(Genesis::Hook::CloudConfig);

use Genesis qw/bail/;

use Genesis::Hook::CloudConfig::Helpers qw/gigabytes megabytes/;

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
			$self->network_definition('jumpbox', strategy => 'ocfp',
				dynamic_subnets => {
					subnets=> ["ocfp-1"],
					allocation => {
						size => 0,
						statics => 0,
					},
					cloud_properties_for_iaas => {
						openstack => {
							'net_id' => $self->network_reference('id'), # TODO: $self->subnet_reference('net_id'),
							'security_groups' => ['default'] #$self->subnet_reference('sgs', 'get_security_groups'),
						},
						stackit => {
							'net_id' => $self->network_reference('id'), # TODO: $self->subnet_reference('net_id'),
							'security_groups' => $self->network_reference('sgs', 'get_sgs_by_names', 'ocfp', 'default'),
						},
						pve => {
							'bridge' => $self->_pve_cpi_setting('pve_network_bridge', 'network_bridge', 'vmbr0'),
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
					stackit => {
						'instance_type' => $self->for_scale({
							dev => 'g1a.1d',
							prod => 'g1a.2d'
						}),
						'boot_from_volume' => $self->TRUE,
						'root_disk' => {'size' => 20}, # in gigabytes
					},
					pve => {
						'cpu'            => scalar($self->env->lookup('bosh-configs.cpi.pve_jumpbox_cpu',  $self->for_scale({ dev => 2, prod => 4 }, 2))),
						'ram'            => scalar($self->env->lookup('bosh-configs.cpi.pve_jumpbox_ram',  $self->for_scale({ dev => 4096, prod => 8192 }, 4096))),
						'disk'           => scalar($self->env->lookup('bosh-configs.cpi.pve_jumpbox_disk', $self->for_scale({ dev => 32768, prod => 65536 }, 32768))),
						'network_bridge' => $self->_pve_cpi_setting('pve_network_bridge', 'network_bridge', 'vmbr0'),
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
					stackit => {
						'type' => $self->for_scale({
              dev  => 'storage_premium_perf6',
              prod => 'storage_premium_perf8'
            })
					},
					pve => {
						'storage'     => $self->_pve_cpi_setting('pve_disk_storage', 'disk_storage', 'local-lvm'),
						'disk_format' => scalar($self->env->lookup('bosh-configs.cpi.pve_disk_format', 'raw')),
					},
				},
			),
		],
	});

	$self->done($config);

	return 1;

}

sub get_sgs_by_names {
	my ($self, $subnet_data, $ref, @names) = @_;
	my @ids = map {$subnet_data->{$ref}{$_}{id}} @names;
	# TODO: Error checking
	return \@ids
}

# _pve_cpi_setting - resolve a PVE CPI setting from the env file, then the OCFP vault config, then a default {{{
sub _pve_cpi_setting {
	my ($self, $env_key, $vault_key, $default) = @_;
	my $value = scalar($self->env->lookup("bosh-configs.cpi.$env_key", undef));
	$value //= scalar($self->env->ocfp_config_lookup("cpi.pve.$vault_key", undef));
	$value //= $default;
	bail(
		"No PVE %s configured for %s: set #c{bosh-configs.cpi.%s} in the ".
		"environment file, or run #g{ocfp vault populate} so the OCFP config ".
		"provides #c{cpi/pve:%s}.",
		$vault_key, $self->env->name, $env_key, $vault_key
	) unless defined($value) && length($value);
	return $value;
}

# }}}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
