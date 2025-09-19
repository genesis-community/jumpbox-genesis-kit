package Genesis::Hook::Addon::Jumpbox::Who v3.0.0;

use v5.20;
use warnings; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'./.genesis/lib'}

use parent qw(Genesis::Hook::Addon);
use Genesis qw/run/;

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0-rc.20');
	return $obj;
}

sub cmd_details {
	return
	"See who is logged into the jumpbox, via SSH.\n".
	"Any additional arguments will be passed to the ssh command.\n"
	"This requires the ability to login via SSH.\n";
}

sub perform {
	my ($self) = @_;

	# Get jumpbox IP
	my ($ips_json, $rc, $err) = run('bosh vms --json | jq -r \'.Tables[0].Rows[0].ips\'');
	chomp($ips_json);
	my @ips = split(/\s+/, $ips_json);

	# Execute SSH command with 'who' command
	my @args = @{$self->{args}};
	exec('ssh', $ips[0], @args, '--', 'who')
		or bail("Failed to execute SSH command: $!");
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
