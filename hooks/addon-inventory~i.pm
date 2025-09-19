package Genesis::Hook::Addon::Jumpbox::Inventory v3.0.0;

use v5.20;
use warnings; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'./.genesis/lib'}

use parent qw(Genesis::Hook::Addon);
use Genesis qw/run bail/;

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0-rc.20');
	return $obj;
}

sub cmd_details {
	return
	"Take an inventory of software installed on the jumpbox and the versions present.\n".
	"This addon runs the inventory BOSH errand on the jumpbox deployment.\n";
}

sub perform {
	my ($self) = @_;

	# Run inventory errand
	my ($out, $rc) = $self->env->bosh->execute({interactive => 1},'run-errand','inventory');

	if ($rc != 0) {
		bail("Failed to run the inventory errand");
	}

	return $self->done();
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
