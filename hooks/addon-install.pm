package Genesis::Hook::Addon::Jumpbox::Install;

use v5.20;
use warnings; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'./.genesis/lib'}

use parent qw(Genesis::Hook::Addon);
use Genesis qw/run bail info/;

# Include get_jumpbox_ip method from mixin
BEGIN {
	require File::Basename;
	my $mixin_file = File::Basename::dirname(__FILE__) . '/lib/_get_jumpbox_ip.pm';
	do $mixin_file or die "Failed to include addon mixin $mixin_file: $!";
}

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0');
	# Check options and args
	my $opts = $obj->parse_options([
		'destination=s',
		'sha=s',
		'v|verbose'
		# Will need more options to support S3 downloads, such as access key, secret, region, url, etc.
	]);
	bail("You must provide a single URL to install") unless @{$obj->{args}} == 1;
	$obj->{opts} = $opts;
	return $obj;
}

sub cmd_details {
	return
		"Install a package onto the jumpbox\n\n".
		"Usage: $ENV{GENESIS_CALL_ENV} $ENV{GENESIS_CALLED_COMMAND} $ENV{GENESIS_ADDON_SCRIPT} url [-d destination] [--sha <sha256>] [-v]\n\n".
		"Valid url formats:\n".
		"  http(s)://example.com/file.tar.gz\n".
	#	"  s3://bucket-name/path/to/file.tgz\n".   # Future
	#	"  http(s)://example.com/something.deb\n". # Future
		"  path/to/local/file\n\n"
}

sub perform {
	my ($self) = @_;

	my $url = $self->{args}[0];
	my $opts = $self->{opts};

	# Determine type of file to install
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
		"Unsupported file source protocol '%s'. Supported protocols are: %s", # s3 in future
		$file_src_type,
		join(", ", @supported_src_types)
	) if !in_array($file_src_type, @supported_src_types);

	# Get jumpbox IP
	my $jumpbox_ip = $self->_get_jumpbox_ip();

	# Download file to jumpbox
	my ($filename) = $url =~ m{^(?:.*://).*([^/]+)(?:$|[#\?])};

	my $remote_tmp_file = "/tmp/".($filename || 'downloaded_file');
	if ($file_src_type eq 'http') {
		my $curl_cmd = "curl -fsSL -o '$remote_tmp_file' '$url'";
		info("Downloading file from %s to jumpbox...", $url);
		my ($out, $rc) = run({interactive => $opts->{verbose}}, "ssh", $jumpbox_ip, $curl_cmd);
		$out //= 'See above' if $opts->{verbose};
		bail("Failed to download file from %s: %s", $url, $out||'<no output') if $rc != 0;
	} elsif ($file_src_type eq 's3') {
		# This will work once we have RubidiumStudios/s3 installed on the jumpbox
		# See https://github.com/RubidiumStudios/s3/blob/e92bbce18eeed2faffd21c926a9a8483740a18e6/main.go#L165
		my ($bucket, $key) = $url =~ m{^s3://([^/]+)/(.*)$};
		bail("Invalid S3 URL format. Must be s3://bucket-name/path/to/file") unless $bucket && $key;
		my $cmd = "s3 get  --to '$remote_tmp_file' '$bucket/$key'";
		info("Downloading file from S3 %s to jumpbox...", $url);
		my ($out, $rc) = run({interactive => $opts->{verbose}}, "ssh", $jumpbox_ip, $cmd);
		$out //= 'See above' if $opts->{verbose};
		bail("Failed to download file from %s: %s", $url, $out||'<no output>') if $rc != 0;
	} elsif ($file_src_type eq 'local') {
		info("Uploading local file %s to jumpbox...", $url);
		bail("Local file %s does not exist", $url) unless -f $url;
		my ($out, $rc) = run({interactive => $opts->{verbose}}, "scp", $url, "$jumpbox_ip:$remote_tmp_file");
		$out //= 'See above' if $opts->{verbose};
		bail("Failed to upload local file %s: %s", $url, $out||'<no output>') if $rc != 0;
	}
	# Verify SHA256 if provided
	if ($opts->{sha}) {
		info("Verifying SHA256 checksum...");
		my $sha_cmd = "sha256sum '$remote_tmp_file' | awk '{print \$1}'";
		my ($out, $rc) = run({interactive => $opts->{verbose}}, "ssh", $jumpbox_ip, $sha_cmd);
		$out //= 'See above' if $opts->{verbose};
		bail("Failed to compute SHA256 checksum of downloaded file: %s", $out||'<no output>') if $rc != 0;
		chomp($out);
		if ($out ne $opts->{sha}) {
			# Delete the bad file?
			#run({interactive => $opts->{verbose}}, "ssh", $jumpbox_ip, "rm -f '$remote_tmp_file'");
			bail("SHA256 checksum mismatch! Expected %s but got %s", $opts->{sha}, $out);
		}
		info("SHA256 checksum verified.");
	}

	# If tarball, untar to destination
	if ($file_type eq 'tarball') {
		my $dirname = $filename =~ s{\.tar\.gz$}{}r;
		my $destination = $opts->{destination} || '/opt/'.$dirname;
		info("Extracting tarball to %s...", $destination);
		my $untar_cmd = "mkdir -p '$destination' && tar -xzf '$remote_tmp_file' -C '$destination'";
		my ($out, $rc) = run({interactive => $opts->{verbose}}, "ssh", $jumpbox_ip, $untar_cmd);
		$out //= 'See above' if $opts->{verbose};
		bail("Failed to extract tarball to %s: %s", $destination, $out||'<no output>') if $rc != 0;
		info("Extraction complete.");
		# Clean up
		run({interactive => $opts->{verbose}}, "ssh", $jumpbox_ip, "rm -f '$remote_tmp_file'");
		info("Installation complete.");
		return $self->done(1);
	} else {
		# We'll just put the file in the destination
		my $destination = $opts->{destination} || '/opt/'.$filename;
		info("Moving file to %s...", $destination);
		my $mv_cmd = "mv '$remote_tmp_file' '$destination'";
		my ($out, $rc) = run({interactive => $opts->{verbose}}, "ssh", $jumpbox_ip, $mv_cmd);
		$out //= 'See above' if $opts->{verbose};
		bail("Failed to move file to %s: %s", $destination, $out||'<no output>') if $rc != 0;
		info("Installation complete.");
		return $self->done(1);
	}
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
