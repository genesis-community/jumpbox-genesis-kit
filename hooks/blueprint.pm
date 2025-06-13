#!/usr/bin/env perl
package Genesis::Hook::Blueprint::Jumpbox v3.0.4;

use strict;
use warnings;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}
use parent qw(Genesis::Hook::Blueprint);

use Genesis qw/bail mkfile_or_fail/;

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->{features} = [$obj->env->features];
  $obj->{files} = [];
  $obj->check_minimum_genesis_version('3.1.0-rc.9');
  return $obj;
}

sub perform {
  my ($blueprint) = @_; # $blueprint is '$self'

  $blueprint->add_files(qw(
    manifests/jumpbox.yml
    manifests/releases/jumpbox.yml
    manifests/releases/toolbelt.yml
  ));

  my @invalid = ();
  for my $feature ($blueprint->features) {
    if ($feature =~ /^(ocfp|bastion|dev-tools)$/) {
      $blueprint->add_files("manifests/${feature}.yml")
    } elsif ($feature eq 'openvpn') {
      $blueprint->add_files(qw(
        manifests/addons/openvpn.yml
        manifests/releases/openvpn.yml
        manifests/releases/networking.yml
      ));
    } elsif (-f "$ENV{GENESIS_ROOT}/ops/${feature}.yml") {
      $blueprint->add_files("$ENV{GENESIS_ROOT}/ops/${feature}.yml")
    } else {
      push @invalid, $feature;
    }
  }
  bail(
    "Invalid %s encountered: %s",
    count_nouns(scalar(@invalid), 'feature', suppress_count => 1),
    join(', ', @invalid)
  ) if @invalid;

  # TODO: Make the users file dynamic, and add exodus data for capturing what
  #       user details were deployed.
 
  $blueprint->add_files("manifests/users.ym")
    if $blueprint->env->lookup('params.users_file');

  $blueprint->_dynamic_network_fragment if $blueprint->want_feature('ocfp');
  $blueprint->done();
}

sub _dynamic_network_fragment {
  my $self = shift;

  # OCFP dynamic network connection
  #  my @azs = map {"$ENV{GENESIS_ENVIRONMENT}-$_"} @{$self->env->lookup('params.availability_zones', ['z1'])};

  # Determine instance count and IPs from ocfp config
  my $subnets = $self->env->ocfp_config_lookup('net.subnets');
  my $prefix = $self->env->ocfp_subnet_prefix;
  my $az_map = $self->env->director_exodus_lookup('/network')->{azs};

  my (@ips, @azs) = ();
  for my $subnet (sort grep {/^$prefix/} keys %$subnets) {
    my $ip = $subnets->{$subnet}{'reserved-ips'}{'jumpbox_ip'};
    next unless $ip;
    push @ips, $ip;
    push @azs, $az_map->{$subnets->{$subnet}{az}}{name};
  }

  bail(
    "Could not locate any available static IPs in azs %s",
    join(', ',@azs)
  ) unless @ips;

  my $network_name = "$ENV{GENESIS_ENVIRONMENT}.$ENV{GENESIS_TYPE}.net-jumpbox";
  my $dynamic_network_fragment = <<"EOF";
exodus:
  ips: ${\(join ',', @ips)}

instance_groups:
- name: jumpbox
  instances: ${\(scalar @ips)}
  azs:${\(join "\n  - ", '','(( replace ))', @azs)}
  networks:
  - (( replace ))
  - name: $network_name
    static_ips:${\(join "\n    - ", '', @ips)}
EOF
  my $network_file = "manifests/network.dynamic.yml";
  mkfile_or_fail($self->env->kit->path($network_file), 0644, $dynamic_network_fragment);
  $self->add_files($network_file);
}

1;
