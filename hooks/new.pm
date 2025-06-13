#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker
package Genesis::Hook::New::Jumpbox v2.7.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook);

use Genesis qw/run prompt_for info prompt_for_boolean/;

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0-rc.20');
	return $obj;
}

sub perform {
	my ($self) = @_;

	# OpenVPN configuration
	my $openvpn;
	prompt_for('openvpn', 'boolean',
		'Would you like to use OpenVPN to better control user access?',
		\$openvpn);

	my (@vpn_client_routes, @vpn_dns_servers, @vpn_dns_search_domains);

	if ($openvpn eq 'true') {
		prompt_for('vpn_client_routes', 'multi-line',
			'What routes should OpenVPN push to connecting clients? (CIDR format e.g. 10.4.0.0/16)',
			'--min 1', \@vpn_client_routes);

		prompt_for('vpn_dns_servers', 'multi-line',
			'What DNS servers should OpenVPN advertise to connecting clients?',
			'--min 1', \@vpn_dns_servers);

		prompt_for('vpn_dns_search_domains', 'multi-line',
			'What DNS search domains should OpenVPN advertise to connecting clients?',
			'--min 1', \@vpn_dns_search_domains);
	}

	# Create environment file
	my $env_file = $ENV{GENESIS_ROOT} . "/." . $ENV{GENESIS_ENVIRONMENT} . ".yml";
	my $final_env_file = $ENV{GENESIS_ROOT} . "/" . $ENV{GENESIS_ENVIRONMENT} . ".yml";

	open(my $fh, '>', $env_file) or die "Cannot open $env_file: $!";

	print $fh "kit:\n";
	print $fh "  name:    $ENV{GENESIS_KIT_NAME}\n";
	print $fh "  version: $ENV{GENESIS_KIT_VERSION}\n";

	if ($openvpn eq 'true') {
		print $fh "  features:\n";
		print $fh "    - openvpn\n";
	}
	print $fh "\n";

	# Add genesis config block
	my ($config_block, $rc) = run('genesis_config_block');
	print $fh $config_block;

	print $fh "params: {}\n";

	if ($openvpn eq 'true') {
		print $fh "  vpn_client_routes:\n";
		for my $route (@vpn_client_routes) {
			my ($network, $cidr) = split('/', $route);
			my $mask = $self->cidr2mask($cidr);
			print $fh "    - $network $mask\n";
		}

		print $fh "  vpn_iptables_forward:\n";
		for my $route (@vpn_client_routes) {
			print $fh "    - -s 172.31.255.0/24 -d $route -m conntrack --ctstate NEW -j ACCEPT -m comment --comment 'vpn -> lan'\n";
			print $fh "    - -s $route -d 172.31.255.0/24 -m conntrack --ctstate NEW -j ACCEPT -m comment --comment 'lan -> vpn'\n";
		}
		print $fh "    - -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT\n";

		print $fh "  vpn_dns_servers:\n";
		for my $dns (@vpn_dns_servers) {
			print $fh "    - $dns\n";
		}

		print $fh "  vpn_dns_search_domains:\n";
		for my $domain (@vpn_dns_search_domains) {
			print $fh "    - $domain\n";
		}
		print $fh "\n";
	}

	# User configuration
	my $addusers;
	prompt_for('addusers', 'boolean',
		'Would you like to add users to this jumpbox instance?',
		\$addusers);

	if ($addusers eq 'true') {
		print $fh "  users:\n";
	}

	while ($addusers eq 'true') {
		my $user;
		prompt_for('user', 'line',
			'Account login name',
			'--validation \'/^[a-z_][a-z0-9_-]{0,30}$/\'',
			\$user);

		my $shell;
		prompt_for('shell', 'line',
			"What shell will #C{$user} use? (/bin/bash, /bin/zsh, etc.)",
			'--default /bin/bash',
			\$shell);

		my $pubkey;
		prompt_for('pubkey', 'line',
			"What is $user's public SSH key?",
			'--validation \'/ssh-/\'',
			\$pubkey);

		print $fh "    - name:  $user\n";
		print $fh "      shell: $shell\n";
		print $fh "      ssh_keys:\n";
		print $fh "        # you can add more keys as needed...\n";
		print $fh "        - $pubkey\n";
		print $fh "\n";

		prompt_for('addusers', 'boolean',
			'Would you like to add another user to this jumpbox instance?',
			\$addusers);
	}

	close $fh;

	# Check if we need to fix the params line
	my $last_line = `tail -n1 "$env_file"`;
	chomp($last_line);

	if ($last_line ne "params: {}") {
		run('sed -e \'s/^params: {}$/params:/\' "$1" > "$2"', $env_file, $final_env_file);
		unlink($env_file);
	} else {
		run('mv "$1" "$2"', $env_file, $final_env_file);
	}

	# Offer environment editor
	run({ interactive => 1 }, 'offer_environment_editor');

	return $self->done();
}

# Convert CIDR notation to subnet mask
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

1;
