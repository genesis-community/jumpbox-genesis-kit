package VaultUserManager;

use v5.20;
use warnings;

use Genesis qw(run load_yaml_file bail);
use JSON;

our $VERSION = '2.0';

=head1 NAME

VaultUserManager2 - Genesis-integrated vault user management

=head1 DESCRIPTION

A Genesis-integrated version of VaultUserManager that uses Genesis libraries
instead of direct safe commands. Requires a Genesis::Hook::Addon object to
provide access to Genesis::Env and vault operations.

=head1 SYNOPSIS

	# Initialize with a Hook::Addon object
	my $manager = VaultUserManager2->new(
		addon => $addon_hook_object,
		env_base => 'secret/custom'  # optional override
	);

	# Same API as original VaultUserManager
	$manager->load_releases();
	my $user = $manager->get_user('alice');
	$manager->save_user($user);

=cut

sub new {
	my ($class, %args) = @_;

	# Require addon hook object
	bail("VaultUserManager2 requires an 'addon' parameter containing a Genesis::Hook::Addon object")
		unless $args{addon} && ref($args{addon}) =~ /^Genesis::Hook::Addon/;

	my $addon = $args{addon};
	my $env = $addon->env;

	return bless({
		addon     => $addon,
		env       => $env,
		vault     => $env->vault,
		env_base  => $env->secrets_base,
		mode      => $args{mode} || 'environment',
	}, $class);
}


# Generate vault path based on mode and subpath
sub vault_path {
	my ($self, $subpath) = @_;
	$subpath = $subpath ? "/$subpath" : '';

	if ($self->{mode} eq 'config') {
		# Use OCFP config lookup for config mode - this returns the path structure
		# The jumpbox/users portion needs to be appended to get the full path
		return "jumpbox/users$subpath";
	} else {
		# Environment path: $env_base/users
		return sprintf("%s/users%s",
			$self->{env_base},
			$subpath
		);
	}
}

# Check if a vault path exists
sub exists {
	my ($self, $path) = @_;

	if ($self->{mode} eq 'config') {
		my $config_path = $path =~ m|^jumpbox/| ? $path : $self->vault_path($path);
		my ($value, $found_path) = $self->{env}->ocfp_config_lookup($config_path);
		# Path exists if found_path is defined (even if value is null/undef)
		return defined $found_path;
	} else {
		my $full_path = $path =~ m|^/| ? $path : $self->vault_path($path);
		eval {
			my $result = $self->{vault}->get($full_path);
			return defined $result;
		};
		return 0 if $@;  # Path doesn't exist if get throws error
		return 1;
	}
}

# Read data from vault path
sub read {
	my ($self, $path) = @_;

	if ($self->{mode} eq 'config') {
		my $config_path = $path =~ m|^jumpbox/| ? $path : $self->vault_path($path);
		return scalar($self->{env}->ocfp_config_lookup($config_path));
	} else {
		my $full_path = $path =~ m|^/| ? $path : $self->vault_path($path);
		my $data;
		eval {
			$data = $self->{vault}->get_path($full_path);
		};
		# Return undef if path doesn't exist or other error
		return undef if $@;
		return $data;
	}
}

# Write data to vault path
sub write {
	my ($self, $path, $data) = @_;

	if ($self->{mode} eq 'config') {
		# Config mode is read-only, cannot write to OCFP config structure
		bail("Cannot write to config mode - OCFP config structure is read-only");
	} else {
		my $full_path = $path =~ m|^/| ? $path : $self->vault_path($path);
		eval {
			$self->{vault}->set_path($full_path, $data);
			return 1;
		};
		return 0 if $@;  # Failed to write
		return 1;
	}
}

# Delete vault path
sub delete {
	my ($self, $path) = @_;

	if ($self->{mode} eq 'config') {
		# Config mode is read-only, cannot delete from OCFP config structure
		bail("Cannot delete from config mode - OCFP config structure is read-only");
	} else {
		my $full_path = $path =~ m|^/| ? $path : $self->vault_path($path);
		eval {
			$self->{vault}->delete_path($full_path);
			return 1;
		};
		return 0 if $@;  # Failed to delete
		return 1;
	}
}

# List paths in vault
sub list {
	my ($self, $path) = @_;
	my $full_path = $path ? $self->vault_path($path) : $self->vault_path();

	# Use Genesis run command to execute safe paths
	my ($out, $rc, $err) = run(
		{interactive => 0, stderr => undef},
		'safe', 'paths', $full_path
	);

	if ($rc != 0) {
		return [];
	}

	my @paths = split /\n/, $out;
	return \@paths;
}

### User-specific methods ###

# Get all users from manifest
sub get_all_users {
	my ($self) = @_;
	my $manifest = $self->read('manifest');
	return [] unless $manifest && $manifest->{users};

	my $users_data = $manifest->{users};
	if (!ref($users_data)) {
		# Try to decode JSON if it's a string
		eval {
			$users_data = JSON->new->decode($users_data);
		};
		return [] if $@;
	}

	return $users_data;
}

# Get specific user data
sub get_user {
	my ($self, $username) = @_;

	# Read user metadata
	my $metadata = $self->read("$username/metadata");
	return undef unless $metadata;

	# Read SSH keys
	my $keys_data = $self->read("$username/ssh_keys");
	my $ssh_keys = [];

	if ($keys_data && $keys_data->{keys}) {
		if (ref($keys_data->{keys})) {
			$ssh_keys = $keys_data->{keys};
		} else {
			eval {
				$ssh_keys = JSON->new->decode($keys_data->{keys});
			};
		}
	}

	# Parse teams from JSON string
	my $teams = [];
	if ($metadata->{teams}) {
		if (ref($metadata->{teams})) {
			$teams = $metadata->{teams};
		} else {
			eval {
				$teams = JSON->new->decode($metadata->{teams});
			};
		}
	}

	return {
		name => $username,
		shell => $metadata->{shell} || '/bin/bash',
		teams => $teams,
		ssh_keys => $ssh_keys,
	};
}

# Save user data
sub save_user {
	my ($self, $user) = @_;

	my $username = $user->{name};
	return 0 unless $username;

	# Save metadata
	my $metadata = {
		shell => $user->{shell} || '/bin/bash',
		teams => JSON->new->encode($user->{teams} || []),
	};

	return 0 unless $self->write("$username/metadata", $metadata);

	# Save SSH keys
	my $keys_data = {
		keys => JSON->new->encode($user->{ssh_keys} || []),
	};

	return 0 unless $self->write("$username/ssh_keys", $keys_data);

	# Update manifest
	$self->_update_manifest();

	return 1;
}

# Delete user
sub delete_user {
	my ($self, $username) = @_;

	# Delete user data
	$self->delete("$username/metadata");
	$self->delete("$username/ssh_keys");

	# Update manifest
	$self->_update_manifest();

	return 1;
}

# Update manifest with current user list
sub _update_manifest {
	my ($self) = @_;

	# Get all user directories
	my $paths = $self->list('');
	my @users;

	foreach my $path (@$paths) {
		next unless $path =~ m|/([^/]+)/metadata$|;
		my $username = $1;
		next if $username eq 'manifest';

		my $user = $self->get_user($username);
		push @users, $user if $user;
	}

	# Save updated manifest
	$self->write('manifest', {
		users => JSON->new->canonical->encode(\@users),
		updated => time(),
	});
}

# Sync from config data
sub sync_from_config {
	my ($self, $config_data) = @_;

	my $users = $config_data->{users} || [];
	my $success = 1;

	foreach my $user (@$users) {
		unless ($self->save_user($user)) {
			warn "Failed to save user: $user->{name}\n";
			$success = 0;
		}
	}

	return $success;
}

### Mode management methods ###

# Set operating mode
sub set_mode {
	my ($self, $mode) = @_;
	bail("Invalid mode: $mode. Must be 'config' or 'environment'")
		unless $mode eq 'config' || $mode eq 'environment';
	$self->{mode} = $mode;
}

# Get current mode
sub get_mode {
	my ($self) = @_;
	return $self->{mode};
}

# Check if config path exists
sub config_exists {
	my ($self) = @_;

	my $original_mode = $self->{mode};
	$self->set_mode('config');

	my $exists = $self->exists('manifest');

	$self->set_mode($original_mode);
	return $exists;
}

# Find config path - OCFP handles path resolution automatically
sub find_config_path {
	my ($self) = @_;

	my $original_mode = $self->{mode};
	$self->set_mode('config');

	# Check if config exists via OCFP lookup
	my $exists = $self->exists('manifest');

	$self->set_mode($original_mode);
	return $exists ? 'config' : undef;
}

# Sync from config to environment
sub sync_config_to_environment {
	my ($self) = @_;

	# Save current mode
	my $original_mode = $self->{mode};

	# Read from config
	$self->set_mode('config');
	my $config_users = $self->get_all_users();

	# Switch to environment mode
	$self->set_mode('environment');

	# Get existing environment users
	my $env_users = $self->get_all_users();
	my %env_users_by_name = map { $_->{name} => $_ } @$env_users;

	# Merge users (config users take precedence for init)
	my @merged_users;
	my %seen;

	# Add all config users
	foreach my $user (@$config_users) {
		push @merged_users, $user;
		$seen{$user->{name}} = 1;
	}

	# Add environment users that aren't in config
	foreach my $user (@$env_users) {
		unless ($seen{$user->{name}}) {
			push @merged_users, $user;
		}
	}

	# Save merged users to environment
	my $success = 1;
	foreach my $user (@merged_users) {
		unless ($self->save_user($user)) {
			warn "Failed to sync user: $user->{name}\n";
			$success = 0;
		}
	}

	# Update manifest
	$self->_update_manifest() if $success;

	# Restore original mode
	$self->set_mode($original_mode);

	return $success;
}


# Access to underlying Genesis objects
sub addon { $_[0]->{addon} }
sub env   { $_[0]->{env} }
sub vault { $_[0]->{vault} }

1;

# vim: ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1 nu
