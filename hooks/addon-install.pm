package Genesis::Hook::Addon::Jumpbox::Install;

use v5.20;
use warnings; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'./.genesis/lib'}

use parent qw(Genesis::Hook::Addon);
use Genesis qw/bail info warning/;

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0');
	# Check options and args
	my $opts = $obj->parse_options([
		'destination=s',
		'sha=s',
		'v|verbose',
		'cleanup-on-failure'
		# Will need more options to support S3 downloads, such as access key, secret, region, url, etc.
	]);
	bail("You must provide a single URL to install") unless @{$obj->{args}} == 1;
	$obj->{opts} = $opts;
	return $obj;
}

sub cmd_details {
	return
		"Install a package onto the jumpbox\n\n".
		"Usage: $ENV{GENESIS_CALL_ENV} $ENV{GENESIS_CALLED_COMMAND} $ENV{GENESIS_ADDON_SCRIPT} url [-d destination] [--sha <sha256>] [--cleanup-on-failure] [-v]\n\n".
		"Valid url formats:\n".
		"  http(s)://example.com/file.tar.gz\n".
	#	"  s3://bucket-name/path/to/file.tgz\n".   # Future
	#	"  http(s)://example.com/something.deb\n". # Future
		"  path/to/local/file\n\n".
		"Options:\n".
		"  -d, --destination <path>  Destination path (default: /opt/<filename>)\n".
		"  --sha <sha256>            SHA256 checksum to verify\n".
		"  --cleanup-on-failure      Remove file if SHA verification fails (default: keep for debugging)\n".
		"  -v, --verbose             Show detailed output\n\n"
}

sub perform {
	my ($self) = @_;

	# Initialize
	my $url = $self->{args}[0];

	# Validate BOSH director connection
	bail("Unable to connect to BOSH director. Ensure BOSH is configured for this environment.")
		unless $self->bosh;

	# Parse URL to determine file type and source
	my ($file_type, $file_src_type, $filename) = $self->_parse_url($url);

	# Fetch file to jumpbox
	my $remote_tmp_file = "/tmp/".($filename || 'downloaded_file');
	if ($file_src_type eq 'http') {
		$self->_download_http($url, $remote_tmp_file);
	} elsif ($file_src_type eq 's3') {
		$self->_download_s3($url, $remote_tmp_file);
	} elsif ($file_src_type eq 'local') {
		$self->_upload_local($url, $remote_tmp_file);
	}

	# Verify file exists and has content
	$self->_verify_file_exists($remote_tmp_file);

	# Verify checksum if requested
	$self->_verify_sha($remote_tmp_file);

	# Install file based on type
	if ($file_type eq 'tarball') {
		$self->_install_tarball($remote_tmp_file, $filename);
	} else {
		$self->_install_file($remote_tmp_file, $filename);
	}

	return $self->done(1);
}

### Helper Methods

# _shell_escape - Escape string for safe shell use {{{
sub _shell_escape {
	my ($self, $str) = @_;
	return "''" unless defined $str;
	# Replace single quotes with '\'' and wrap in single quotes
	$str =~ s/'/'\\''/g;
	return "'$str'";
}
# }}}

# _run_cmd - Execute command on jumpbox via BOSH director {{{
sub _run_cmd {
	my ($self, $cmd, %extra_opts) = @_;
	return $self->bosh->run_on_instance(
		$cmd,
		target => 'jumpbox',
		interactive => $self->{opts}{verbose} ? 1 : 0,
		%extra_opts
	);
}
# }}}

# _check_result - Verify command result and bail on failure {{{
sub _check_result {
	my ($self, $result, $error_msg) = @_;
	return if $result->{exit_code} == 0;

	# In verbose mode, user already saw the output
	if ($self->{opts}{verbose}) {
		bail($error_msg, 'See above');
	}

	# Collect error information from all available fields
	# - error: BOSH-level errors (connection, SSH setup, etc.)
	# - stderr: Command's stderr output
	# - stdout: Command's stdout output (may contain error messages)
	my @error_parts;
	push @error_parts, "Error: $result->{error}" if $result->{error};
	push @error_parts, "Stderr: $result->{stderr}" if $result->{stderr};
	push @error_parts, "Stdout: $result->{stdout}" if $result->{stdout};

	my $error_details = @error_parts ? join("\n", @error_parts) : '<no output>';
	bail($error_msg, $error_details);
}
# }}}

# _parse_url - Determine file type and source type from URL {{{
sub _parse_url {
	my ($self, $url) = @_;

	my $file_type
		= $url =~ /\.t(ar\.)gz$/ ? 'tarball'
	#	: $url =~ /\.deb$/       ? 'deb' # Not supporting deb for now
		:                          'unknown';

	my $file_src_type
		= $url =~ m{^https?://} ? 'http'
	#	: $url =~ m{^s3://}     ? 's3'
		: $url =~ m{^(.*)://}   ? $1
		:                         'local';

	my @supported_src_types = qw/http local/; # s3 in future
	bail(
		"Unsupported file source protocol '%s'. Supported protocols are: %s",
		$file_src_type,
		join(", ", @supported_src_types)
	) unless grep { $_ eq $file_src_type } @supported_src_types;

	# Extract filename: strip protocol, query/fragment, and trailing slashes
	my $path = $url;
	$path =~ s{^[^:]+://}{}; # Remove protocol if present
	$path =~ s{[?#].*$}{};   # Remove query string and fragment
	$path =~ s{/+$}{};       # Remove trailing slashes
	my ($filename) = $path =~ m{([^/]+)$};

	return ($file_type, $file_src_type, $filename);
}
# }}}

# _download_http - Download file from HTTP URL {{{
sub _download_http {
	my ($self, $url, $remote_tmp_file) = @_;

	info("Downloading file from %s to jumpbox...", $url);
	my $url_escaped = $self->_shell_escape($url);
	my $file_escaped = $self->_shell_escape($remote_tmp_file);
	my $curl_cmd = "curl -fsSL -o $file_escaped $url_escaped";
	my $result = $self->_run_cmd($curl_cmd);
	$self->_check_result($result, "Failed to download file from $url: %s");
}
# }}}

# _download_s3 - Download file from S3 {{{
sub _download_s3 {
	my ($self, $url, $remote_tmp_file) = @_;

	# This will work once we have RubidiumStudios/s3 installed on the jumpbox
	# See https://github.com/RubidiumStudios/s3/blob/e92bbce18eeed2faffd21c926a9a8483740a18e6/main.go#L165
	my ($bucket, $key) = $url =~ m{^s3://([^/]+)/(.*)$};
	bail("Invalid S3 URL format. Must be s3://bucket-name/path/to/file") unless $bucket && $key;

	info("Downloading file from S3 %s to jumpbox...", $url);
	my $file_escaped = $self->_shell_escape($remote_tmp_file);
	my $s3path_escaped = $self->_shell_escape("$bucket/$key");
	my $cmd = "s3 get  --to $file_escaped $s3path_escaped";
	my $result = $self->_run_cmd($cmd);
	$self->_check_result($result, "Failed to download file from $url: %s");
}
# }}}

# _upload_local - Upload local file to jumpbox {{{
sub _upload_local {
	my ($self, $url, $remote_tmp_file) = @_;

	info("Uploading local file %s to jumpbox...", $url);
	bail("Local file %s does not exist", $url) unless -f $url;

	my $results = $self->bosh->upload_to_instance(
		local_path => $url,
		remote_path => $remote_tmp_file,
		target => 'jumpbox'
	);

	unless ($results && @$results) {
		info("Warning: file upload completed but no confirmation received");
		return;
	}

	my $result = $results->[0];
	$self->_check_result($result, "Failed to upload local file $url: %s");
}
# }}}

# _verify_file_exists - Validate remote file exists and has non-zero size {{{
sub _verify_file_exists {
	my ($self, $remote_file) = @_;

	info("Verifying file was transferred successfully...");

	# test -s returns true if file exists and has size > 0
	my $file_escaped = $self->_shell_escape($remote_file);
	my $result = $self->_run_cmd("test -s $file_escaped");

	if ($result->{exit_code} != 0) {
		bail("File was not successfully transferred or is empty: %s", $remote_file);
	}

	info("File verified on jumpbox");
}
# }}}

# _verify_sha - Verify SHA256 checksum of remote file {{{
sub _verify_sha {
	my ($self, $remote_file) = @_;

	return unless $self->{opts}{sha};

	info("Verifying SHA256 checksum...");
	my $file_escaped = $self->_shell_escape($remote_file);
	my $sha_cmd = "sha256sum $file_escaped | awk '{print \$1}'";

	# Always run non-interactively to capture hash output, even in verbose mode
	my $result = $self->bosh->run_on_instance(
		$sha_cmd,
		target => 'jumpbox',
		interactive => 0
	);
	$self->_check_result($result, "Failed to compute SHA256 checksum of downloaded file: %s");

	my $out = $result->{stdout};
	chomp($out) if $out;

	if ($out ne $self->{opts}{sha}) {
		# Optionally clean up the bad file
		if ($self->{opts}{'cleanup-on-failure'}) {
			my $rm_cmd = "rm -f $file_escaped";
			$self->_run_cmd($rm_cmd);
			bail(
				"SHA256 checksum mismatch! Expected %s but got %s\n".
				"File has been removed from jumpbox.",
				$self->{opts}{sha}, $out
			);
		} else {
			bail(
				"SHA256 checksum mismatch! Expected %s but got %s\n".
				"File kept at %s for debugging. Use --cleanup-on-failure to auto-remove.",
				$self->{opts}{sha}, $out, $remote_file
			);
		}
	}
	info("SHA256 checksum verified.");
}
# }}}

# _validate_destination - Ensure destination path is safe {{{
sub _validate_destination {
	my ($self, $destination) = @_;

	# Must be an absolute path
	bail("Destination must be an absolute path (start with /): %s", $destination)
		unless $destination =~ m{^/};

	# Must not contain .. (path traversal)
	bail("Destination path must not contain '..' (path traversal): %s", $destination)
		if $destination =~ m{\.\.};

	# Critical system directories that must not be overwritten (exact match only)
	my @forbidden_exact = qw(
		/ /bin /sbin /usr /lib /lib64 /boot /dev /proc /sys /etc /root
		/var/vcap /var/vcap/bosh /var/vcap/monit /var/vcap/micro /var/vcap/micro_bosh
		/var/vcap/jobs /var/vcap/packages /var/vcap/data /var/vcap/data/packages
	);
	foreach my $forbidden (@forbidden_exact) {
		bail("Destination cannot be critical system/BOSH directory: %s", $destination)
			if $destination eq $forbidden;
	}

	# Warn if not under typical safe installation paths
	# Allow /opt, /var/vcap/store, /var/vcap/data/*, /var/vcap/jobs/*, /var/vcap/packages/*, /srv, /home
	unless ($destination =~ m{^/(?:opt|var/vcap/(?:store|data/[^/]+|jobs/[^/]+|packages/[^/]+)|srv|home)/}) {
		warning("Destination %s is outside typical installation paths", $destination);
	}
}
# }}}

# _install_tarball - Extract tarball to destination {{{
sub _install_tarball {
	my ($self, $remote_file, $filename) = @_;

	my $dirname = $filename =~ s{\.tar\.gz$}{}r;
	my $destination = $self->{opts}{destination} || '/opt/'.$dirname;

	# Validate destination path for security
	$self->_validate_destination($destination);

	info("Extracting tarball to %s...", $destination);
	my $dest_escaped = $self->_shell_escape($destination);
	my $file_escaped = $self->_shell_escape($remote_file);
	my $untar_cmd = "sudo mkdir -p $dest_escaped && sudo tar -xzf $file_escaped -C $dest_escaped";
	my $result = $self->_run_cmd($untar_cmd);
	$self->_check_result($result, "Failed to extract tarball to $destination: %s");

	info("Extraction complete.");
	# Clean up
	my $rm_cmd = "rm -f $file_escaped";
	$self->_run_cmd($rm_cmd);
	info("Installation complete.");
}
# }}}

# _install_file - Move file to destination {{{
sub _install_file {
	my ($self, $remote_file, $filename) = @_;

	my $destination = $self->{opts}{destination} || '/opt/'.$filename;

	# Validate destination path for security
	$self->_validate_destination($destination);

	info("Moving file to %s...", $destination);
	my $file_escaped = $self->_shell_escape($remote_file);
	my $dest_escaped = $self->_shell_escape($destination);
	my $mv_cmd = "sudo mv $file_escaped $dest_escaped";
	my $result = $self->_run_cmd($mv_cmd);
	$self->_check_result($result, "Failed to move file to $destination: %s");

	info("Installation complete.");
}
# }}}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
