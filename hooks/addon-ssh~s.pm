package Genesis::Hook::Addon::Jumpbox::SSH;

use v5.20;
use warnings; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'./.genesis/lib'}

use parent qw(Genesis::Hook::Addon);
use Genesis qw/run info read_json_from/;

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
	my ($data, $rc) = read_json_from($self->env->bosh->execute('vms', '--json'));
	if ($rc == 0) {
		if ($data->{Tables} && @{$data->{Tables}} && $data->{Tables}[0]{Rows}) {
			my $ips = $data->{Tables}[0]{Rows}[0]{ips} || '';
			my @ips = split(/,\s*/, $ips);

	# Execute SSH command
	my @args = @{$self->{args}};
	exec('ssh', $ips[0], @args)
		or bail("Failed to execute SSH command: $!");
		}
	}
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
