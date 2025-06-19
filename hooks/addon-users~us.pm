package Genesis::Hook::Addon::Jumpbox::Users;

use v5.20;
use warnings; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'./.genesis/lib'}

use parent qw(Genesis::Hook::Addon);
use lib File::Spec->catdir(dirname(__FILE__), 'lib');
use VaultUserManager;

use Genesis qw/run bail info error warning prompt_for_boolean/;
use File::Basename;
use File::Path qw(make_path);
use File::Spec;
use Encode qw(decode encode);
use JSON::PP;
use List::Util qw(min);
use Cwd;
use IO::Socket::SSL;
use Socket;
use Fcntl qw(:flock SEEK_SET);

sub init {
  my $class = shift;
  my $obj = $class->SUPER::init(@_);
  $obj->check_minimum_genesis_version('3.1.0-rc.20');

  # Configuration
  $obj->{config} = {
    TIMEOUT           => 10,             # Initial connection timeout in seconds
    MAX_RETRIES       => 3,               # Maximum number of retry attempts
    RETRY_DELAY_BASE  => 2,               # Base for exponential backoff
    MAX_USERNAMES     => 50,              # Maximum number of usernames to process
    FILE_PERMISSIONS  => 0600,            # Restrictive file permissions
    PROGRESS_WIDTH    => 20,              # Width of progress bar
    BATCH_SIZE        => 1000,             # Number of bytes to read at a time
    MAX_MEMORY_MB     => 100,              # Maximum memory usage warning threshold
    RATE_LIMIT_TOKENS => 10,             # Initial rate limit tokens
    RATE_LIMIT_RATE   => 1,               # Tokens per second
    MAX_LOG_SIZE      => 10 * 1024 * 1024, # 10MB max log size
    OUTPUT_FILE       => Cwd::getcwd() . '/ops/users.yml',
    USER_AGENT        => 'KeysFetcher/1.0',
    LOG_FILE          => '/tmp/users.log',
    VALID_ACTIONS  => {                  # Valid action mappings
      'add'    => 'add',
      'a'      => 'add',
      'remove' => 'remove',
      'r'      => 'remove',
    },
    VALID_SOURCES => {                   # Valid source mappings
      'github'  => {
        host => 'github.com',
        prefix => 'github',
      },
      'gitlab'  => {
        host => 'gitlab.com',
        prefix => 'gitlab',
      },
    },
    DEFAULT_SOURCE => 'github',          # Default source if none specified
    PUB_KEY_PATTERN => qr/^(.+)\.pub$/,  # Pattern to match username from filename
  };

  # Initialize rate limiting
  $obj->{tokens} = $obj->{config}{RATE_LIMIT_TOKENS};
  $obj->{last_update} = time;

  # Initialize counters for summary
  $obj->{processed} = 0;
  $obj->{successful} = 0;
  $obj->{failed} = 0;

  # Track temporary files for cleanup
  $obj->{temp_files} = [];

  return $obj;
}

sub cmd_details {
  return
  "Manage users from GitHub/GitLab SSH keys in ./ops/users.yml\n".
  "Usage: genesis do <env> -- users <init|add|a|remove|r> <[github|gitlab/]username_1> [username_2 ...]\n".
  "Examples:\n".
  "  genesis do <env> -- users init                        # Sync users from Vault config to environment\n".
  "  genesis do <env> -- users add dennisjbell gitlab/wayneeseguin github/krutten\n".
  "  genesis do <env> -- users remove jsmith\n".
  "  genesis do <env> -- users add ./keys/jsmith.pub       # Local pubkey file\n".
  "  genesis do <env> -- users add /path/to/pubkeys/       # Directory of pubkeys\n";
}

sub perform {
  my ($self) = @_;

  # Set up signal handlers for cleanup
  local $SIG{INT} = local $SIG{TERM} = sub {
    $self->print_status('warning', "Interrupted, cleaning up...");
    $self->cleanup_temp_files();
    exit 1;
  };

  # Check if we have enough arguments
  unless (scalar(@{$self->{args}}) >= 1) {
    $self->print_status('error', "Usage: genesis do <env> -- users <init|add|a|remove|r> <[github|gitlab/]username_1> [username_2 ...]");
    $self->print_status('info', "Examples:\n  genesis do <env> -- users init\n  genesis do <env> -- users add dennisjbell gitlab/wayneeseguin github/krutten");
    return 0;
  }

  # Get action
  my $action = shift @{$self->{args}};

  # Handle init command
  if ($action eq 'init') {
    return $self->handle_init_command();
  }

  # Validate regular action
  unless (exists $self->{config}{VALID_ACTIONS}{$action}) {
    $self->print_status('error', "Invalid action. Must be one of: init, " . join(", ", sort keys %{$self->{config}{VALID_ACTIONS}}));
    return 0;
  }
  $action = $self->{config}{VALID_ACTIONS}{$action};

  # Check if no usernames provided and try to load from Vault
  if (scalar(@{$self->{args}}) == 0 && $action eq 'add') {
    $self->print_status('info', "No usernames provided, checking Vault for users...");

    my $vault = VaultUserManager->new();
    my $vault_users = $vault->get_all_users();

    if (@$vault_users) {
      $self->print_status('info', "Found " . scalar(@$vault_users) . " users in Vault, using those...");

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
        $self->print_status('warning', "Vault users found but no SSH key sources to process");
        return 0;
      }
    } else {
      $self->print_status('error', "No usernames provided and no users found in Vault");
      return 0;
    }
  }

  # Validate input
  if (scalar(@{$self->{args}}) > $self->{config}{MAX_USERNAMES}) {
    $self->print_status('error', "Too many usernames (max $self->{config}{MAX_USERNAMES})");
    return 0;
  }

  # Initial checks
  eval { $self->check_network() };
  if ($@) {
    $self->print_status('error', "Network check failed: $@");
    return 0;
  }

  $self->log_message('info', "Script started with action '$action' for " . scalar(@{$self->{args}}) . " usernames");

  # Process usernames with sources
  my %processed_users;
  my $data = {
    users => []
  };

  # Read existing YAML into users hash
  my $users = $self->parse_yaml($self->{config}{OUTPUT_FILE});

  if ($action eq 'add') {
    foreach my $input (@{$self->{args}}) {
      $self->{processed}++;

      eval {
        my $result;
        if (-d $input) {
          my $dir_results = $self->detect_and_process_input($input);
          foreach my $res (@$dir_results) {
            if ($res->{success}) {
              $self->process_user_keys($users, $res->{username}, $res->{keys});
              $self->{successful}++;
              my $source = $res->{source} // "file";
              $self->print_status('success',
                "Found " . scalar(@{$res->{keys}}) .
                " valid keys for $res->{username} from $source"
              );
            } else {
              $self->{failed}++;
            }
          }
        } else {
          $result = $self->detect_and_process_input($input);
          if ($result->{success}) {
            $self->process_user_keys($users, $result->{username}, $result->{keys});
            $self->{successful}++;
            my $source = $result->{source} // "file";
            $self->print_status('success',
              "Found " . scalar(@{$result->{keys}}) .
              " valid keys for $result->{username} from $source"
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
        $self->print_status('error', "Failed processing $input: $error");
      }

      sleep 1 unless -f $input || -d $input; # Only sleep for remote requests
    }
  } elsif ($action eq 'remove') {
    foreach my $username_spec (@{$self->{args}}) {
      my $info = $self->parse_username_with_source($username_spec);
      my $username = $info->{username};
      delete $users->{$username};
      $self->print_status('success', "Removed user $username");
    }
  }

  # Generate and write YAML if we have users
  if (keys %$users) {
    $self->print_status('info', "\nGenerating YAML file...");

    eval {
      my $yaml_content = $self->to_yaml($users);

      make_path(File::Basename::dirname($self->{config}{OUTPUT_FILE}))
      unless -d File::Basename::dirname($self->{config}{OUTPUT_FILE});

      $self->write_file_safely($self->{config}{OUTPUT_FILE}, $yaml_content);

      $self->print_status('success', "YAML file '$self->{config}{OUTPUT_FILE}' has been updated successfully");
    };
    if ($@) {
      $self->print_status('error', "Failed to write YAML file: $@");
      return 0;
    }
  } else {
    $self->print_status('warning', "No users remain in YAML file");
  }

  # Print summary
  print("\n=== Summary ===\n");
  $self->print_status('info', "Action performed: $action");
  if ($action eq 'add') {
    $self->print_status('info', "Total users processed: $self->{processed}");
    $self->print_status('success', "Successful: $self->{successful}");
    $self->print_status('error', "Failed: $self->{failed}");
  } else {
    $self->print_status('info', "Users removed: " . scalar(@{$self->{args}}));
  }

  $self->log_message('info', "Successfully updated users ops file: $self->{config}{OUTPUT_FILE}");

  # Clean up
  $self->cleanup_temp_files();

	return $self->done();
}

# Core processing functions
sub detect_and_process_input {
  my ($self, $input) = @_;

  # Case 1: Directory
  if (-d $input) {
    $self->print_status('info', "Processing directory: $input");
    return $self->process_directory($input);
  }

  # Case 2: .pub file
  if ($input =~ $self->{config}{PUB_KEY_PATTERN} && -f $input) {
    $self->print_status('info', "Processing public key file: $input");
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
    $self->print_status('error', "Invalid public key filename format: $filename");
    return { success => 0, username => undef, keys => [] };
  }
  my $username = $1;

  # Validate username
  eval { $self->validate_username($username) };
  if ($@) {
    $self->print_status('error', "Invalid username from file $filename: $@");
    return { success => 0, username => $username, keys => [] };
  }

  # Read and validate key content
  open(my $fh, '<', $filepath) or die "Cannot open $filepath: $!";
  my $content = do { local $/; <$fh> };
  close($fh);

  my @valid_keys;
  foreach my $key (split /\n/, $self->ensure_utf8($content)) {
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
    $self->print_status('error', "No valid SSH keys found in $filepath");
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

  opendir(my $dh, $directory) or die "Cannot open directory $directory: $!";
  my @pub_files = grep { /$self->{config}{PUB_KEY_PATTERN}/ } readdir($dh);
  closedir($dh);

  foreach my $file (@pub_files) {
    my $filepath = File::Spec->catfile($directory, $file);
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

  eval { $self->validate_username($username) };
  if ($@) {
    $self->print_status('error', "Invalid username: $@");
    return {
      success => 0,
      username => $username,
      keys => []
    };
  }

  unless ($self->check_rate_limit()) {
    $self->log_message('warning', "Rate limit reached, waiting...");
    sleep 1;
  }

  $self->consume_token();

  # Fetch SSH keys
  my $content = $self->fetch_https_content($source, $username);
  my @valid_keys;

  foreach my $key (split /\n/, $self->ensure_utf8($content)) {
    next unless $key =~ /\S/;
    if ($key =~ /^(ssh-rsa|ssh-dss|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)\s+[A-Za-z0-9+\/]+[=]{0,3}(\s+.+)?$/) {
      push @valid_keys, $key;
    }
  }

  if (@valid_keys) {
    return {
      success => 1,
      username => $username,
      keys => \@valid_keys,
      source => $source
    };
  } else {
    $self->print_status('error', "No valid SSH keys found for $username from $source");
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

  open(my $fh, '<', $file) or die "Cannot open $file: $!";
  my @lines = <$fh>;
  close($fh);

  my $current_user;
  foreach my $line (@lines) {
    chomp $line;
    if ($line =~ /^\s*-\s*name:\s*['"]?(.*?)['"]?\s*$/) {
      $current_user = $1;
      $users{$current_user} = {
        shell => '/bin/bash',  # Default shell
        ssh_keys => []
      };
    }
    elsif ($line =~ /^\s*shell:\s*['"]?(.*?)['"]?\s*$/ && $current_user) {
      $users{$current_user}->{shell} = $1;
    }
    elsif ($line =~ /^\s*-\s*(.*?)\s*$/ && $current_user) {
      my $key = $1;
      # Skip append directives and empty lines
      next if $key =~ /^\(\(\s*append\s*\)\)$/ || $key =~ /^\s*$/;
      push @{$users{$current_user}->{ssh_keys}}, $key;
    }
  }

  return \%users;
}

sub to_yaml {
  my ($self, $users_ref) = @_;
  my $yaml = "---\nusers:\n";

  # Sort usernames for consistent output
  foreach my $username (sort keys %$users_ref) {
    my $user = $users_ref->{$username};
    $yaml .= "  - name: " . $self->yaml_escape($username) . "\n";
    $yaml .= "    shell: " . $self->yaml_escape($user->{shell}) . "\n";
    $yaml .= "    ssh_keys:\n";
    # Add append directive as first element
    $yaml .= "      - (( append ))\n";

    # Add all SSH keys
    foreach my $key (@{$user->{ssh_keys}}) {
      my $escaped_key = $key;
      $escaped_key =~ s/\n/\n      /g;
      $yaml .= "      - " . $self->yaml_escape($escaped_key) . "\n";
    }
  }

  return $yaml;
}

sub yaml_escape {
  my ($self, $str) = @_;
  return $str unless $str =~ /[:"'\\\n]/;
  $str =~ s/'/'\\''/g;
  return "'$str'";
}

# Network and HTTP functions
sub check_network {
  my ($self) = @_;
  my $host = 'github.com';
  my $sock = IO::Socket::INET->new(
    PeerAddr => $host,
    PeerPort => 443,
    Proto    => 'tcp',
    Timeout  => 5
  );

  die "Network connectivity check failed: $!\n" unless $sock;
  close($sock);
  return 1;
}

sub with_timeout {
  my ($self, $timeout, $code) = @_;

  eval {
    local $SIG{ALRM} = sub { die "Operation timed out\n" };
    alarm($timeout);
    $code->();
    alarm(0);
  };
  alarm(0);
  die $@ if $@;
}

sub fetch_https_content {
  my ($self, $source, $username) = @_;
  my $host = $self->{config}{VALID_SOURCES}{$source}{host};
  my $path = "/$username.keys";
  my $retry_count = 0;
  my $content = '';

  while ($retry_count < $self->{config}{MAX_RETRIES}) {
    no warnings 'exiting';
    eval {
      $self->with_timeout($self->{config}{TIMEOUT} * ($retry_count + 1), sub {
        my $socket = IO::Socket::SSL->new(
          PeerHost => $host,
          PeerPort => 443,
          SSL_verify_mode => SSL_VERIFY_NONE,
          Timeout => $self->{config}{TIMEOUT} * ($retry_count + 1)
        ) or die "Cannot create SSL socket: $@";

        print $socket "GET $path HTTP/1.1\r\n";
        print $socket "Host: $host\r\n";
        print $socket "User-Agent: $self->{config}{USER_AGENT}\r\n";
        print $socket "Connection: close\r\n\r\n";

        my $in_headers = 1;
        my $response = '';

        while (1) {
          my $chunk = '';
          my $bytes = sysread($socket, $chunk, $self->{config}{BATCH_SIZE});
          last unless defined $bytes && $bytes > 0;
          $response .= $chunk;
        }

        close $socket;

        # Parse response
        my $parsed = $self->parse_http_response($response);

        if ($parsed->{status_code} == 200) {
          $content = $parsed->{body};
        } elsif ($parsed->{status_code} == 404) {
          die "User not found\n";
        } elsif ($parsed->{status_code} == 403) {
          die "Rate limit exceeded\n";
        } else {
          die "HTTP Error: " . $parsed->{status_code} . "\n";
        }
      });
      last;  # Success, exit retry loop
    };

    if ($@) {
      $retry_count++;
      my $error = $@;
      if ($retry_count < $self->{config}{MAX_RETRIES}) {
        my $delay = $self->{config}{RETRY_DELAY_BASE} ** $retry_count;
        $self->print_status('warning', "Attempt $retry_count failed: $error. Retrying in $delay seconds...");
        sleep($delay);
        next;
      }
      die $error;
    }
  }

  return $content;
}

sub parse_http_response {
  my ($self, $response) = @_;
  my %result;

  # Split into headers and body
  my ($headers, $body) = split /\r\n\r\n/, $response, 2;

  # Parse status line
  my ($http_version, $status_code, $reason) =
  $headers =~ m{^HTTP/(\d\.\d)\s+(\d+)\s+(.+?)\r\n}
    or die "Invalid HTTP response\n";

  # Parse headers into hash
  my %headers;
  while ($headers =~ /^(.+?):\s*(.+?)\r\n/mg) {
    $headers{lc $1} = $2;
  }

  return {
    status_code => $status_code,
    headers => \%headers,
    body => $body
  };
}

# Rate limiting functions
sub check_rate_limit {
  my ($self) = @_;
  my $now = time;
  my $elapsed = $now - $self->{last_update};
  $self->{tokens} = min($self->{config}{RATE_LIMIT_TOKENS},
    $self->{tokens} + $elapsed * $self->{config}{RATE_LIMIT_RATE});
  $self->{last_update} = $now;
  return $self->{tokens} >= 1;
}

sub consume_token {
  my ($self) = @_;
  $self->{tokens}--;
}

# File and cleanup functions
sub write_file_safely {
  my ($self, $filename, $content) = @_;
  my $old_mask = umask(0077);  # Ensure restrictive permissions

  eval {
    my $tmp_file = "$filename.tmp";
    $self->register_temp_file($tmp_file);

    open(my $fh, '>', $tmp_file) or die "Cannot open $tmp_file: $!";
    flock($fh, LOCK_EX) or die "Cannot lock $tmp_file: $!";

    seek($fh, 0, SEEK_SET) or die "Cannot seek $tmp_file: $!";
    truncate($fh, 0) or die "Cannot truncate $tmp_file: $!";

    print $fh $self->encode_output($content) or die "Cannot write to $tmp_file: $!";

    close($fh) or die "Cannot close $tmp_file: $!";

    rename($tmp_file, $filename) or die "Cannot rename $tmp_file to $filename: $!";
    chmod($self->{config}{FILE_PERMISSIONS}, $filename) or die "Cannot set permissions: $!";
  };
  my $error = $@;
  umask($old_mask);  # Restore original umask

  die $error if $error;
}

sub register_temp_file {
  my ($self, $filename) = @_;
  push @{$self->{temp_files}}, $filename;
}

sub cleanup_temp_files {
  my ($self) = @_;
  unlink $_ for @{$self->{temp_files}};
}

# Utility functions
sub print_status {
  my ($self, $type, $message) = @_;
  my %colors = (
    info    => "\033[36m",  # Cyan
    success => "\033[32m",  # Green
    warning => "\033[33m",  # Yellow
    error   => "\033[31m",  # Red
    reset   => "\033[0m"    # Reset
  );

  # Check if terminal supports colors
  if (!-t STDOUT || $ENV{NO_COLOR}) {
    %colors = map { $_ => '' } keys %colors;
  }

  print "$colors{$type}\[$type\]$colors{reset} $message\n";
  $self->log_message($type, $message);
}

sub log_message {
  my ($self, $type, $message) = @_;
  my $timestamp = scalar(localtime());
  my $log_message = "[$timestamp] [$type] $message\n";

  eval {
    $self->rotate_log_if_needed();

    open(my $fh, '>>', $self->{config}{LOG_FILE}) or die "Cannot open log file: $!";
    flock($fh, LOCK_EX) or die "Cannot lock log file: $!";
    print $fh $log_message;
    close($fh);
  };
  warn "Failed to write to log file: $@" if $@;
}

sub rotate_log_if_needed {
  my ($self) = @_;
  return unless -f $self->{config}{LOG_FILE};

  my $size = -s $self->{config}{LOG_FILE};
  return unless $size && $size > $self->{config}{MAX_LOG_SIZE};

  my $backup = $self->{config}{LOG_FILE} . ".1";
  rename($self->{config}{LOG_FILE}, $backup);
}

sub validate_username {
  my ($self, $username) = @_;

  # Check length
  die "Username too short\n" if length($username) < 1;
  die "Username too long\n" if length($username) > 39;

  # Check valid characters and pattern
  die "Invalid username format\n"
  unless $username =~ /^[a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38}$/;

  # Check for consecutive hyphens
  die "Invalid username format: consecutive hyphens\n"
  if $username =~ /--/;

  # Check start/end characters
  die "Invalid username format: cannot start with hyphen\n"
  if $username =~ /^-/;
  die "Invalid username format: cannot end with hyphen\n"
  if $username =~ /-$/;

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
    unless (exists $self->{config}{VALID_SOURCES}{$prefix}) {
      die "Invalid source prefix '$prefix'. Valid sources are: " .
      join(", ", sort keys %{$self->{config}{VALID_SOURCES}}) . "\n";
    }
    $source = $prefix;
  }

  return {
    username => $username,
    source => $source,
  };
}

sub ensure_utf8 {
  my ($self, $str) = @_;
  return $str if Encode::is_utf8($str);
  return decode('UTF-8', $str, Encode::FB_CROAK);
}

sub encode_output {
  my ($self, $str) = @_;
  return encode('UTF-8', $str, Encode::FB_CROAK);
}

sub format_progress_bar {
  my ($self, $current, $total) = @_;
  my $width = $self->{config}{PROGRESS_WIDTH};
  my $progress = $current / $total;
  my $filled = int($progress * $width);
  return sprintf "[%s%s] %d%%",
  "=" x $filled,
  " " x ($width - $filled),
  $progress * 100;
}

sub handle_init_command {
  my ($self) = @_;

  $self->print_status('info', "Initializing users from Vault config...");

  # Create VaultUserManager instance
  my $vault = VaultUserManager->new();

  # Try to find config path across different environment types
  my $config_env_type = $vault->find_config_path();

  unless ($config_env_type) {
    $self->print_status('warning', "No users found in any Vault config path");
    $self->print_status('info', "Tried paths for environment types: mgmt, ocf");
    $self->print_status('info', "Checking environment Vault path for existing users...");

    # Check if we should look for users in environment path
    my $env_users = $vault->get_all_users();
    if (@$env_users) {
      $self->print_status('info', "Found " . scalar(@$env_users) . " users in environment Vault path");
    } else {
      $self->print_status('info', "No users found in environment Vault path either");
    }
    return 1;
  }

  # Set the found environment type
  if ($config_env_type ne $vault->env_type()) {
    $self->print_status('info', "Found config in '$config_env_type' environment type (current: " . $vault->env_type() . ")");
    $vault->env_type($config_env_type);
  }

  # Sync from config to environment
  $self->print_status('info', "Syncing users from config to environment...");
  my $success = $vault->sync_config_to_environment();

  unless ($success) {
    $self->print_status('error', "Failed to sync users from config to environment");
    return 0;
  }

  # Get all users from environment path after sync
  my $users = $vault->get_all_users();
  $self->print_status('info', "Synced " . scalar(@$users) . " users to environment Vault");

  # Now generate ops/users.yml from the synced users
  $self->print_status('info', "Generating ops/users.yml from Vault users...");

  # Process each user and fetch their SSH keys
  my $data = { users => [] };
  my $processed = 0;
  my $failed = 0;

  foreach my $user (@$users) {
    $processed++;
    my $user_data = {
      name => $user->{name},
      shell => $user->{shell} || '/bin/bash',
      ssh_keys => ['(( append ))']
    };

    # Process SSH keys
    foreach my $key_spec (@{$user->{ssh_keys} || []}) {
      if ($key_spec =~ /^ssh-/) {
        # Direct SSH key
        push @{$user_data->{ssh_keys}}, $key_spec;
      } elsif ($key_spec =~ /^(github|gitlab):(.+)$/) {
        # Fetch from GitHub/GitLab
        my ($source, $username) = ($1, $2);
        $self->print_status('info', "Fetching SSH keys for $username from $source...");

        my $keys = $self->fetch_keys($source, $username);
        if ($keys && @$keys) {
          push @{$user_data->{ssh_keys}}, @$keys;
          $self->print_status('success', "Added " . scalar(@$keys) . " keys for $username");
        } else {
          $self->print_status('warning', "Failed to fetch keys for $username from $source");
          $failed++;
        }
      } elsif ($key_spec =~ /^file:(.+)$/) {
        # Read from file
        my $file_path = $1;
        if (-f $file_path) {
          my $key_content = $self->read_file($file_path);
          if ($key_content) {
            push @{$user_data->{ssh_keys}}, $key_content;
            $self->print_status('success', "Added key from file: $file_path");
          }
        } else {
          $self->print_status('warning', "Key file not found: $file_path");
          $failed++;
        }
      }
    }

    push @{$data->{users}}, $user_data;
  }

  # Write to ops/users.yml
  $self->write_yaml($self->{config}{OUTPUT_FILE}, $data);

  $self->print_status('success', "Initialization complete!");
  $self->print_status('info', "Processed: $processed users, Failed: $failed");
  $self->print_status('info', "Users written to: $self->{config}{OUTPUT_FILE}");

  return 1;
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
