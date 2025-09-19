package Genesis::Hook::New::Jumpbox v3.0.0;

use v5.20;
use warnings;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook);

use Genesis qw/mkfile_or_fail bail/;
use Genesis::UI qw/prompt_for_boolean prompt_for_line/;

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

  # OpenVPN configuration
  my $openvpn = prompt_for_boolean(
    'Would you like to use OpenVPN to better control user access?'
  );

  my (@vpn_client_routes, @vpn_dns_servers, @vpn_dns_search_domains);

  if ($openvpn) {
    @vpn_client_routes = prompt_for_multiline(
      'What routes should OpenVPN push to connecting clients? (CIDR format e.g. 10.4.0.0/16)'
    );

    @vpn_dns_servers = prompt_for_multiline(
      'What DNS servers should OpenVPN advertise to connecting clients?', '--validation', 'ip'
    );

    @vpn_dns_search_domains = prompt_for_multiline(
      'What DNS search domains should OpenVPN advertise to connecting clients?'
    );
  }

  # Build environment file content
  my $file_content = "kit:\n";
  $file_content .= "  name:    $ENV{GENESIS_KIT_NAME}\n";
  $file_content .= "  version: $ENV{GENESIS_KIT_VERSION}\n";

  if ($openvpn) {
    $file_content .= "  features:\n";
    $file_content .= "    - openvpn\n";
  }

  $file_content .= "\n";
  $file_content .= $self->env->genesis_config_block;

  # Start params section
  my $params_content = "";

  if ($openvpn) {
    $params_content .= "  vpn_client_routes:\n";
    for my $route (@vpn_client_routes) {
      my ($network, $cidr) = split('/', $route);
      my $mask = $self->cidr2mask($cidr);
      $params_content .= "    - $network $mask\n";
    }

    $params_content .= "  vpn_iptables_forward:\n";
    for my $route (@vpn_client_routes) {
      $params_content .= "    - -s 172.31.255.0/24 -d $route -m conntrack --ctstate NEW -j ACCEPT -m comment --comment 'vpn -> lan'\n";
      $params_content .= "    - -s $route -d 172.31.255.0/24 -m conntrack --ctstate NEW -j ACCEPT -m comment --comment 'lan -> vpn'\n";
    }
    $params_content .= "    - -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT\n";

    $params_content .= "  vpn_dns_servers:\n";
    for my $dns (@vpn_dns_servers) {
      $params_content .= "    - $dns\n";
    }

    $params_content .= "  vpn_dns_search_domains:\n";
    for my $domain (@vpn_dns_search_domains) {
      $params_content .= "    - $domain\n";
    }
  }

  # User configuration
  my $addusers = prompt_for_boolean(
    'Would you like to add users to this jumpbox instance?'
  );

  if ($addusers) {
    $params_content .= "  users:\n";

    while ($addusers) {
      my $user = prompt_for_line(
        'Account login name',
        { validation => qr/^[a-z_][a-z0-9_-]{0,30}$/ }
      );

      my $shell = prompt_for_line(
        "What shell will #C{$user} use? (/bin/bash, /bin/zsh, etc.)",
        { default => '/bin/bash' }
      );

      my $pubkey = prompt_for_line(
        "What is #C{$user}'s public SSH key?",
        { validation => qr/ssh-/ }
      );

      $params_content .= "    - name:  $user\n";
      $params_content .= "      shell: $shell\n";
      $params_content .= "      ssh_keys:\n";
      $params_content .= "        # you can add more keys as needed...\n";
      $params_content .= "        - $pubkey\n";
      $params_content .= "\n";

      $addusers = prompt_for_boolean(
        'Would you like to add another user to this jumpbox instance?'
      );
    }
  }

  # Add params section
  if ($params_content) {
    $file_content .= "params:\n";
    $file_content .= $params_content;
  } else {
    $file_content .= "params: {}\n";
  }

  # Write the environment file
  $self->env->write_manifest($file_content);

  return $self->done();
}
# }}}

# cidr2mask - Convert CIDR notation to subnet mask {{{
sub cidr2mask {
  my ($self, $cidr) = @_;
  my $mask = "";
  my $full_octets = int($cidr/8);
  my $partial_octet = $cidr % 8;

  for my $i (0..3) {
    if ($i < $full_octets) {
      $mask .= "255";
    } elsif ($i == $full_octets) {
      $mask .= (256 - 2**(8-$partial_octet));
    } else {
      $mask .= "0";
    }
    $mask .= "." if $i < 3;
  }

  return $mask;
}
# }}}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
