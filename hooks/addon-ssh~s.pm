package Genesis::Hook::Addon::Jumpbox::SSH;

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
	"SSH (interactively) into the jumpbox.\n".
	"Any additional arguments will be passed to the ssh command.\n";
}

sub perform {
	my ($self) = @_;

	# Get jumpbox IP
	my ($ips_json, $rc, $err) = run('bosh vms --json | jq -r \'.Tables[0].Rows[0].ips\'');
	chomp($ips_json);
	my @ips = split(/\s+/, $ips_json);

	# Execute SSH command
	my @args = @{$self->{args}};
	exec('ssh', $ips[0], @args);

	# We won't reach here if exec is successful
	return $self->done();
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
