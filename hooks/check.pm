# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
package Genesis::Hook::Check::Jumpbox;

use v5.20;
use warnings;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook::Check);

use Genesis qw/info/;

# init - Initialize the hook {{{
sub init {
  my ($class, %ops) = @_;
  my $obj = $class->SUPER::init(%ops);
  $obj->check_minimum_genesis_version('3.1.0');
  return $obj;
}
# }}}

# perform - Main hook execution {{{
sub perform {
  my ($self) = @_;
  my $ok = 1;
  
  # Cloud Config checks
  if ($ENV{GENESIS_CLOUD_CONFIG}) {
    $self->start_check("Checking cloud config");
    
    my @errors;
    push @errors, $self->env->missing_cloud_config_keys(
      vm_type   => [$self->env->lookup('params.jumpbox_vm_type',   'jumpbox')],
      disk_type => [$self->env->lookup('params.jumpbox_disk_pool', 'jumpbox')],
      network   => [$self->env->lookup('params.jumpbox_network',   'jumpbox')]
    );
    
    if (@errors) {
      $self->check_result(0, join("\n", @errors));
      $ok = 0;
    } else {
      $self->check_result(1);
    }
  }
  
  # Check users file if specified
  my $users_file = $self->env->lookup('params.users_file', '');
  if ($users_file) {
    $self->start_check("Checking users file");
    
    if (!-f $self->env->path($users_file)) {
      $self->check_result(0, "Missing users file '$users_file'");
      $ok = 0;
    } else {
      $self->check_result(1);
    }
  }
  
  return $self->done($ok);
}
# }}}

1;
