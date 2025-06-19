package Genesis::Hook::Blueprint::Jumpbox;

use v5.20;
use warnings;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}
use parent qw(Genesis::Hook::Blueprint);

use Genesis qw/bail mkfile_or_fail/;

# init - Initialize the hook {{{
sub init {
  my ($class, %ops) = @_;
  my $obj = $class->SUPER::init(%ops);
  $obj->check_minimum_genesis_version('3.1.0');
  return $obj;
}
# }}}

# perform - Main hook execution {{{
sub perform {
  my ($self) = @_;

  # Base manifest files
  $self->add_files(qw(
    manifests/jumpbox.yml
    manifests/releases/jumpbox.yml
    manifests/releases/toolbelt.yml
  ));

  # Process features
  my @invalid = ();
  for my $feature ($self->features) {
    if ($feature eq 'shield') {
      bail(
        "The Jumpbox Genesis Kit no longer supplies a 'shield' feature flag.\n".
        "If you wish to back up this jumpbox, please switch to using BOSH\n".
        "runtime configurations to add the shield-agent to the deployment."
      );
    } elsif ($feature eq 'azure') {
      $self->env->notify(warning =>
        "The Jumpbox Genesis Kit no longer supplies a 'azure' feature flag.\n".
        "This is because the 'azure' feature only impacted availability zones\n".
        "and sets, which have no impact on a single-instance deployment."
      );
    } elsif ($feature eq 'proxy') {
      $self->env->notify(warning =>
        "You no longer need to explicitly specify the 'proxy' feature.\n".
        "If you remove it, everything will still work as expected."
      );
    } elsif ($feature eq 'openvpn') {
      $self->add_files(qw(
        manifests/addons/openvpn.yml
        manifests/releases/openvpn.yml
        manifests/releases/networking.yml
      ));
    } elsif ($feature =~ /^(bastion|dev-tools)$/) {
      $self->add_files("manifests/${feature}.yml");
    } elsif ($feature eq 'ocfp') {
      # OCFP handled separately below
    } elsif (-f "$ENV{GENESIS_ROOT}/ops/${feature}.yml") {
      $self->add_files("$ENV{GENESIS_ROOT}/ops/${feature}.yml");
    } else {
      push @invalid, $feature;
    }
  }

  if (@invalid) {
    my $noun = @invalid == 1 ? 'feature' : 'features';
    bail(
      "[ERROR] The following $noun are invalid: %s\n".
      "See the manual for list of valid features.",
      join(', ', map { "#c{$_}" } @invalid)
    );
  }

  # Add users manifest if configured
  $self->add_files("manifests/users.yml")
    if $self->env->lookup('params.users_file');

  # Handle OCFP dynamic network configuration
  $self->_dynamic_network_fragment if $self->want_feature('ocfp');

  return $self->done();
}
# }}}

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

    # Fetch AZ from vault based on environment type
    my $env_type = $self->env->type;
    my $az_path = sprintf("secret/config/%s/%s/net/subnets/%s:az",
      $self->env->ocfp_config_lookup('base'),
      $env_type,
      $subnet
    );
    my $az = eval { $self->env->vault->get($az_path) };
    if (!$az) {
      warning("Could not retrieve AZ for subnet %s from vault path %s", $subnet, $az_path);
      push @azs, undef;
    } else {
      push @azs, $az_map->{$az}{name} || undef;
    }
  }

  bail(
    "Could not locate any available static IPs"
  ) unless @ips;

  my $network_name = "$ENV{GENESIS_ENVIRONMENT}.$ENV{GENESIS_TYPE}.net-jumpbox";

  # Filter out undefined AZs
  my @valid_azs = grep { defined $_ } @azs;
  if (!@valid_azs) {
    bail("No valid availability zones found for Jumpbox instances");
  }

  my $dynamic_network_fragment = <<"EOF";
exodus:
  ips: ${\(join ',', @ips)}

instance_groups:
- name: jumpbox
  instances: ${\(scalar @ips)}
  azs:${\(join "\n  - ", '','(( replace ))', @valid_azs)}
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
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
