package Genesis::Hook::Addon::Jumpbox::Users;
our $VERSION = 'v3.0.0';

use v5.20;
use warnings; # Genesis min perl version is 5.20

BEGIN {
	push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib';
	require File::Basename;
	push @INC, File::Basename::dirname(__FILE__).'/lib';
}

use parent qw(Genesis::Hook::Addon);
use VaultUserManager;
use Service::Github;

use Genesis qw/
	run bail info error warning
	load_yaml_file save_to_yaml_file
	mkfile_or_fail mkdir_or_fail slurp
/;
use File::Basename;

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->check_minimum_genesis_version('3.1.0');

  # Configuration
  $obj->{config} = {
    MAX_USERNAMES   => 50,              # Maximum number of usernames to process
    OUTPUT_FILE     => $obj->env->top->path('ops/users.yml'),
    VALID_ACTIONS   => {                # Valid action mappings
      'add'    => 'add',
      'a'      => 'add',
      'remove' => 'remove',
      'r'      => 'remove',
    },
    VALID_SOURCES   => {                # Valid source names
      'github'  => 'github.com',
      'gitlab'  => 'gitlab.com',
    },
    DEFAULT_SOURCE  => 'github',        # Default source if none specified
    PUB_KEY_PATTERN => qr/^(.+)\.pub$/, # Pattern to match username from filename
  };

  # Initialize counters for summary
  $obj->{processed} = 0;
  $obj->{successful} = 0;
  $obj->{failed} = 0;

  # Cache Service::Github instances per domain
  $obj->{github_services} = {};

  return $obj;
}

sub cmd_details {
  return
  "Manage users from GitHub/GitLab SSH keys in ./ops/users.yml\n".
  "Usage: genesis <env> do users <init|add|a|remove|r> <[github|gitlab/]username_1> [username_2 ...]\n".
  "Examples:\n".
  "  genesis <env> do users init                        # Sync users from Vault config to environment\n".
  "  genesis <env> do users add dennisjbell gitlab/wayneeseguin github/krutten\n".
  "  genesis <env> do users remove jsmith\n".
  "  genesis <env> do users add ./keys/jsmith.pub       # Local pubkey file\n".
  "  genesis <env> do users add /path/to/pubkeys/       # Directory of pubkeys\n";
}

sub perform {
  my ($self) = @_;

  # Check if we have enough arguments
  unless (scalar(@{$self->{args}}) >= 1) {
    error("Usage: genesis <env> do users <init|add|a|remove|r> <[github|gitlab/]username_1> [username_2 ...]");
    info("Examples:\n  genesis <env> do users init\n  genesis <env> do users add dennisjbell gitlab/wayneeseguin github/krutten");
    return 0;
  }

  # Get action
  my $action = shift @{$self->{args}};

  # Handle init command
  return $self->handle_init_command() if $action eq 'init';

  # Validate regular action
  unless (exists $self->{config}{VALID_ACTIONS}{$action}) {
    error("Invalid action. Must be one of: init, %s", join(", ", sort keys %{$self->{config}{VALID_ACTIONS}}));
    return 0;
  }
  $action = $self->{config}{VALID_ACTIONS}{$action};

  # Check if no usernames provided and try to load from Vault
  if (scalar(@{$self->{args}}) == 0 && $action eq 'add') {
    info("No usernames provided, checking Vault for users...");

    my $vault = VaultUserManager->new();
    my $vault_users = $vault->get_all_users();

    if (@$vault_users) {
      info("Found %d users in Vault, using those...", scalar(@$vault_users));

      # Convert Vault users to arguments format
      foreach my $user (@$vault_users) {
        foreach my $key_spec (@{$user->{ssh_keys} || []}) {
          if ($key_spec =~ /^(github|gitlab):(.+)$/) {
            push @{$self->{args}}, "$1/$2";
          } elsif ($key_spec =~ /^file:(.+)$/) {
            push @{$self->{args}}, $1;
          }
        }
      }

      if (scalar(@{$self->{args}}) == 0) {
        warning("Vault users found but no SSH key sources to process");
        return 0;
      }
    } else {
      error("No usernames provided and no users found in Vault");
      return 0;
    }
  }

  # Validate input
  if (scalar(@{$self->{args}}) > $self->{config}{MAX_USERNAMES}) {
    error("Too many usernames (max %d)", $self->{config}{MAX_USERNAMES});
    return 0;
  }

  info("Script started with action '%s' for %d usernames", $action, scalar(@{$self->{args}}));

  # Read existing YAML into users hash
  my $users = $self->parse_yaml($self->{config}{OUTPUT_FILE});

  if ($action eq 'add') {
    foreach my $input (@{$self->{args}}) {
      $self->{processed}++;

      eval {
        my $result = $self->detect_and_process_input($input);
        my @results = ref($result) eq 'ARRAY' ? @$result : ($result);

        foreach my $res (@results) {
          if ($res->{success}) {
            $self->process_user_keys($users, $res->{username}, $res->{keys});
            $self->{successful}++;
            my $source = $res->{source} // "file";
            info("Found %d valid keys for %s from %s",
              scalar(@{$res->{keys}}),
              $res->{username},
              $source
            );
          } else {
            $self->{failed}++;
          }
        }
      };
      if ($@) {
        $self->{failed}++;
        my $error = $@;
        chomp $error;
        error("Failed processing %s: %s", $input, $error);
      }

      sleep 1 unless -f $input || -d $input; # Only sleep for remote requests
    }
  } elsif ($action eq 'remove') {
    foreach my $username_spec (@{$self->{args}}) {
      my $info = $self->parse_username_with_source($username_spec);
      my $username = $info->{username};
      delete $users->{$username};
      info("Removed user %s", $username);
    }
  }

  # Generate and write YAML if we have users
  if (keys %$users) {
    info("\nGenerating YAML file...");

    eval {
      my $output_dir = File::Basename::dirname($self->{config}{OUTPUT_FILE});

      # Create directory if it doesn't exist
      mkdir_or_fail($output_dir, 0755) unless -d $output_dir;

      # Write YAML using Genesis functions
      $self->write_yaml($self->{config}{OUTPUT_FILE}, $users);

      info("YAML file '%s' has been updated successfully", $self->{config}{OUTPUT_FILE});
    };
    if ($@) {
      error("Failed to write YAML file: %s", $@);
      return 0;
    }
  } else {
    warning("No users remain in YAML file");
  }

  # Print summary
  info("\n=== Summary ===");
  info("Action performed: %s", $action);
  if ($action eq 'add') {
    info("Total users processed: %d", $self->{processed});
    info("Successful: %d", $self->{successful});
    error("Failed: %d", $self->{failed}) if $self->{failed};
  } else {
    info("Users removed: %d", scalar(@{$self->{args}}));
  }

  info("Successfully updated users ops file: %s", $self->{config}{OUTPUT_FILE});

	return $self->done();
}

# Core processing functions
sub detect_and_process_input {
  my ($self, $input) = @_;

  # Case 1: Directory
  if (-d $input) {
    info("Processing directory: %s", $input);
    return $self->process_directory($input);
  }

  # Case 2: .pub file
  if ($input =~ $self->{config}{PUB_KEY_PATTERN} && -f $input) {
    info("Processing public key file: %s", $input);
    return $self->process_pubkey_file($input);
  }

  # Case 3: gitlab/ prefix or default github
  return $self->process_remote_user($input);
}

# Function to process a public key file
sub process_pubkey_file {
  my ($self, $filepath) = @_;
  my $filename = File::Basename::basename($filepath);

  # Extract username from filename
  unless ($filename =~ $self->{config}{PUB_KEY_PATTERN}) {
    error("Invalid public key filename format: %s", $filename);
    return { success => 0, username => undef, keys => [] };
  }
  my $username = $1;

  # Validate username
  eval { $self->validate_username($username) };
  if ($@) {
    error("Invalid username from file %s: %s", $filename, $@);
    return { success => 0, username => $username, keys => [] };
  }

  # Read and validate key content (Genesis handles UTF-8)
  my $content = slurp($filepath);

  my @valid_keys;
  foreach my $key (split /\n/, $content) {
    next unless $key =~ /\S/;
    if ($key =~ /^(ssh-rsa|ssh-dss|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)\s+[A-Za-z0-9+\/]+[=]{0,3}(\s+.+)?$/) {
      push @valid_keys, $key;
    }
  }

  if (@valid_keys) {
    return {
      success => 1,
      username => $username,
      keys => \@valid_keys
    };
  } else {
    error("No valid SSH keys found in %s", $filepath);
    return {
      success => 0,
      username => $username,
      keys => []
    };
  }
}

# Function to process a directory of .pub files
sub process_directory {
  my ($self, $directory) = @_;
  my @results;

  my @pub_files = glob("$directory/*.pub");
  foreach my $filepath (@pub_files) {
    push @results, $self->process_pubkey_file($filepath);
  }

  return \@results;
}

# Function to process remote user (github/gitlab)
sub process_remote_user {
  my ($self, $username_spec) = @_;
  my $info = $self->parse_username_with_source($username_spec);
  my $username = $info->{username};
  my $source = $info->{source};

  # Map source to domain
  my $domain = $self->{config}{VALID_SOURCES}{$source};
  unless ($domain) {
    error("Unknown source: %s", $source);
    return {
      success => 0,
      username => $username,
      keys => [],
      source => $source
    };
  }

  # Use Service::Github to fetch keys (works for both GitHub and GitLab!)
  # Cache service instances per domain
  $self->{github_services}{$domain} //= Service::Github->new(domain => $domain);
  my ($keys, $err) = $self->{github_services}{$domain}->get_user_ssh_keys($username);

  if ($err) {
    error("Failed to fetch keys for $username from $source: $err");
    return {
      success => 0,
      username => $username,
      keys => [],
      source => $source
    };
  }

  if (@$keys) {
    return {
      success => 1,
      username => $username,
      keys => $keys,
      source => $source
    };
  } else {
    error("No valid SSH keys found for $username from $source");
    return {
      success => 0,
      username => $username,
      keys => [],
      source => $source
    };
  }
}

# User key processing
sub process_user_keys {
  my ($self, $users_ref, $username, $new_keys) = @_;

  # Create user if doesn't exist
  if (!exists $users_ref->{$username}) {
    $users_ref->{$username} = {
      shell => '/bin/bash',
      ssh_keys => []
    };
  }

  # Track existing keys for deduplication
  my %existing_keys = map { $_ => 1 } @{$users_ref->{$username}->{ssh_keys}};

  # Add new keys if they don't exist
  foreach my $key (@$new_keys) {
    next if exists $existing_keys{$key};  # Skip if already present
    push @{$users_ref->{$username}->{ssh_keys}}, $key;
    $existing_keys{$key} = 1;
  }
}

# YAML handling functions
sub parse_yaml {
  my ($self, $file) = @_;
  my %users;  # Hash to store user data

  return \%users unless -f $file;

  # Use Genesis load_yaml_file instead of manual parsing
  my $yaml_data = load_yaml_file($file);

  # Convert YAML array format to hash format
  if ($yaml_data && $yaml_data->{users}) {
    foreach my $user (@{$yaml_data->{users}}) {
      $users{$user->{name}} = {
        shell => $user->{shell} || '/bin/bash',
        ssh_keys => [grep { $_ ne '(( append ))' } @{$user->{ssh_keys} || []}]
      };
    }
  }

  return \%users;
}

sub write_yaml {
  my ($self, $file, $users_ref) = @_;

  # Convert hash format to YAML array format
  my @users_array;
  foreach my $username (sort keys %$users_ref) {
    my $user = $users_ref->{$username};
    push @users_array, {
      name => $username,
      shell => $user->{shell},
      ssh_keys => ['(( append ))', @{$user->{ssh_keys}}]
    };
  }

  my $data = { users => \@users_array };

  # Use Genesis save_to_yaml_file
  save_to_yaml_file($data, $file);
}

# Network connectivity and rate limiting handled by Service::Github via Genesis curl()

# Utility functions - logging now handled by Genesis functions (info, warning, error)

sub validate_username {
  my ($self, $username) = @_;

  # Check length
  bail "Username too short" if length($username) < 1;
  bail "Username too long" if length($username) > 39;

  # Check valid characters and pattern
  bail "Invalid username format"
    unless $username =~ /^[a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38}$/;

  # Check for consecutive hyphens
  bail "Invalid username format: consecutive hyphens" if $username =~ /--/;

  # Check start/end characters
  bail "Invalid username format: cannot start with hyphen" if $username =~ /^-/;
  bail "Invalid username format: cannot end with hyphen" if $username =~ /-$/;

  return 1;
}

sub parse_username_with_source {
  my ($self, $username_spec) = @_;

  # Default source if no prefix
  my $source = $self->{config}{DEFAULT_SOURCE};
  my $username = $username_spec;

  # Check for source prefix (e.g., "github/username" or "gitlab/username")
  if ($username_spec =~ m{^([\w-]+)/(.+)$}) {
    my $prefix = lc($1);
    $username = $2;

    # Validate source prefix
    bail("Invalid source prefix '%s'. Valid sources are: %s", $prefix,
      join(", ", sort keys %{$self->{config}{VALID_SOURCES}}))
      unless exists $self->{config}{VALID_SOURCES}{$prefix};
    $source = $prefix;
  }

  return {
    username => $username,
    source => $source,
  };
}

sub handle_init_command {
  my ($self) = @_;

  info("Initializing users from Vault config...");

  # Create VaultUserManager instance
  my $vault = VaultUserManager->new();

  # Try to find config path across different environment types
  my $config_env_type = $vault->find_config_path();

  unless ($config_env_type) {
    warning("No users found in any Vault config path");
    info("Tried paths for environment types: mgmt, ocf");
    info("Checking environment Vault path for existing users...");

    # Check if we should look for users in environment path
    my $env_users = $vault->get_all_users();
    if (@$env_users) {
      info("Found %d users in environment Vault path", scalar(@$env_users));
    } else {
      info("No users found in environment Vault path either");
    }
    return 1;
  }

  # Set the found environment type
  if ($config_env_type ne $vault->env_type()) {
    info("Found config in '%s' environment type (current: %s)", $config_env_type, $vault->env_type());
    $vault->env_type($config_env_type);
  }

  # Sync from config to environment
  info("Syncing users from config to environment...");
  my $success = $vault->sync_config_to_environment();

  unless ($success) {
    error("Failed to sync users from config to environment");
    return 0;
  }

  # Get all users from environment path after sync
  my $vault_users = $vault->get_all_users();
  info("Synced %d users to environment Vault", scalar(@$vault_users));

  # Convert Vault users to args format and process via normal add logic
  info("Generating ops/users.yml from Vault users...");

  foreach my $user (@$vault_users) {
    foreach my $key_spec (@{$user->{ssh_keys} || []}) {
      if ($key_spec =~ /^(github|gitlab):(.+)$/) {
        push @{$self->{args}}, "$1/$2";
      } elsif ($key_spec =~ /^file:(.+)$/) {
        push @{$self->{args}}, $1;
      } elsif ($key_spec =~ /^ssh-/) {
        # Direct SSH keys need special handling - store for later
        push @{$self->{direct_keys}{$user->{name}}}, $key_spec;
      }
    }
  }

  # Read existing YAML into users hash
  my $users = $self->parse_yaml($self->{config}{OUTPUT_FILE});

  # Process all remote/file key sources using existing add logic
  foreach my $input (@{$self->{args}}) {
    $self->{processed}++;

    eval {
      my $result = $self->detect_and_process_input($input);
      if ($result->{success}) {
        $self->process_user_keys($users, $result->{username}, $result->{keys});
        $self->{successful}++;
        my $source = $result->{source} // "file";
        info("Found %d valid keys for %s from %s",
          scalar(@{$result->{keys}}),
          $result->{username},
          $source
        );
      } else {
        $self->{failed}++;
      }
    };
    if ($@) {
      $self->{failed}++;
      my $error = $@;
      chomp $error;
      error("Failed processing %s: %s", $input, $error);
    }
  }

  # Add any direct SSH keys from Vault
  if ($self->{direct_keys}) {
    foreach my $username (keys %{$self->{direct_keys}}) {
      $users->{$username} //= { shell => '/bin/bash', ssh_keys => [] };
      foreach my $key (@{$self->{direct_keys}{$username}}) {
        push @{$users->{$username}{ssh_keys}}, $key
          unless grep { $_ eq $key } @{$users->{$username}{ssh_keys}};
      }
    }
  }

  # Write YAML using existing logic
  if (keys %$users) {
    my $output_dir = File::Basename::dirname($self->{config}{OUTPUT_FILE});
    mkdir_or_fail($output_dir, 0755) unless -d $output_dir;
    $self->write_yaml($self->{config}{OUTPUT_FILE}, $users);
    info("Initialization complete!");
    info("Processed: %d, Successful: %d, Failed: %d", $self->{processed}, $self->{successful}, $self->{failed});
    info("Users written to: %s", $self->{config}{OUTPUT_FILE});
  } else {
    warning("No users to write");
  }

  return 1;
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
