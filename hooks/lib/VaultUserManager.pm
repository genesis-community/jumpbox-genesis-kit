#!/usr/bin/perl
package VaultUserManager;

use strict;
use warnings;
use JSON;
use YAML::Tiny;

our $VERSION = '1.0';

sub new {
    my ($class, %args) = @_;
    my $self = {
        env_base  => $args{env_base} || $ENV{GENESIS_SECRETS_BASE} || 'secret',
        bloc_name => $args{bloc_name} || _get_bloc_name(),
        safe_cmd  => $args{safe_cmd} || 'safe',
        mode      => $args{mode} || 'environment', # 'environment' or 'config'
        env_type  => $args{env_type} || _get_env_type(), # 'mgmt' or 'ocf'
    };
    bless $self, $class;
    return $self;
}

sub _get_bloc_name {
    my $env_name = $ENV{GENESIS_ENVIRONMENT} || '';
    my ($bloc) = split /-/, $env_name;
    return $bloc || 'default';
}

sub _get_env_type {
    my $env_name = $ENV{GENESIS_ENVIRONMENT} || '';
    
    # Check if environment name contains 'ocf' or 'mgmt'
    if ($env_name =~ /ocf/) {
        return 'ocf';
    } elsif ($env_name =~ /mgmt/) {
        return 'mgmt';
    }
    
    # Default to mgmt if neither is found
    return 'mgmt';
}

sub vault_path {
    my ($self, $subpath) = @_;
    $subpath = $subpath ? "/$subpath" : '';
    
    if ($self->{mode} eq 'config') {
        # Config path: secret/config/$bloc_name/$env_type/jumpbox/users
        return sprintf("secret/config/%s/%s/jumpbox/users%s", 
            $self->{bloc_name},
            $self->{env_type},
            $subpath
        );
    } else {
        # Environment path: $GENESIS_SECRETS_BASE/users
        return sprintf("%s/users%s", 
            $self->{env_base},
            $subpath
        );
    }
}

sub safe_exec {
    my ($self, @args) = @_;
    my $cmd = join(' ', $self->{safe_cmd}, @args);
    my $output = `$cmd 2>&1`;
    my $rc = $? >> 8;
    return wantarray ? ($output, $rc) : $output;
}

sub exists {
    my ($self, $path) = @_;
    my $full_path = $path =~ m|^/| ? $path : $self->vault_path($path);
    my ($output, $rc) = $self->safe_exec('exists', $full_path);
    return $rc == 0;
}

sub read {
    my ($self, $path) = @_;
    my $full_path = $path =~ m|^/| ? $path : $self->vault_path($path);
    my ($output, $rc) = $self->safe_exec('read', $full_path);
    
    if ($rc != 0) {
        return undef;
    }
    
    # Parse YAML output from safe
    my $data = {};
    eval {
        my $yaml = YAML::Tiny->read_string($output);
        $data = $yaml->[0] if $yaml && @$yaml;
    };
    
    return $data;
}

sub write {
    my ($self, $path, $data) = @_;
    my $full_path = $path =~ m|^/| ? $path : $self->vault_path($path);
    
    # Convert data to key=value pairs for safe write
    my @args = ('write', $full_path);
    foreach my $key (sort keys %$data) {
        my $value = $data->{$key};
        if (ref($value)) {
            $value = JSON->new->canonical->encode($value);
        }
        push @args, "$key=$value";
    }
    
    my ($output, $rc) = $self->safe_exec(@args);
    return $rc == 0;
}

sub delete {
    my ($self, $path) = @_;
    my $full_path = $path =~ m|^/| ? $path : $self->vault_path($path);
    my ($output, $rc) = $self->safe_exec('delete', '-y', $full_path);
    return $rc == 0;
}

sub list {
    my ($self, $path) = @_;
    my $full_path = $path ? $self->vault_path($path) : $self->vault_path();
    my ($output, $rc) = $self->safe_exec('paths', $full_path);
    
    if ($rc != 0) {
        return [];
    }
    
    my @paths = split /\n/, $output;
    return \@paths;
}

# User-specific methods

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
    
    return {
        name => $username,
        shell => $metadata->{shell} || '/bin/bash',
        teams => $metadata->{teams} || [],
        ssh_keys => $ssh_keys,
    };
}

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

sub delete_user {
    my ($self, $username) = @_;
    
    # Delete user data
    $self->delete("$username/metadata");
    $self->delete("$username/ssh_keys");
    
    # Update manifest
    $self->_update_manifest();
    
    return 1;
}

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

# Mode management methods

sub set_mode {
    my ($self, $mode) = @_;
    die "Invalid mode: $mode. Must be 'config' or 'environment'\n" 
        unless $mode eq 'config' || $mode eq 'environment';
    $self->{mode} = $mode;
}

sub get_mode {
    my ($self) = @_;
    return $self->{mode};
}

# Sync users from config path to environment path
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

# Check if config path exists and has users
sub config_exists {
    my ($self) = @_;
    
    my $original_mode = $self->{mode};
    $self->set_mode('config');
    
    my $exists = $self->exists('manifest');
    
    $self->set_mode($original_mode);
    return $exists;
}

# Try multiple environment types to find config
sub find_config_path {
    my ($self) = @_;
    
    my $original_mode = $self->{mode};
    my $original_env_type = $self->{env_type};
    $self->set_mode('config');
    
    # Try current environment type first
    if ($self->exists('manifest')) {
        $self->set_mode($original_mode);
        return $self->{env_type};
    }
    
    # Try alternate environment types
    my @env_types = ('mgmt', 'ocf');
    foreach my $env_type (@env_types) {
        next if $env_type eq $self->{env_type}; # Skip current type
        
        $self->{env_type} = $env_type;
        if ($self->exists('manifest')) {
            my $found_type = $env_type;
            $self->{env_type} = $original_env_type;
            $self->set_mode($original_mode);
            return $found_type;
        }
    }
    
    # Restore original values
    $self->{env_type} = $original_env_type;
    $self->set_mode($original_mode);
    return undef;
}

# Get or set environment type
sub env_type {
    my ($self, $type) = @_;
    if (defined $type) {
        $self->{env_type} = $type;
    }
    return $self->{env_type};
}

1;