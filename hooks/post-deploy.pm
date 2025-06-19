package Genesis::Hook::PostDeploy::Jumpbox;

use v5.20;
use warnings;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook);

use Genesis qw/info run/;
use JSON::PP;

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

  if ($ENV{GENESIS_DEPLOY_RC} == 0) {
    # Get jumpbox IP addresses
    my ($out, $rc, $err) = run('bosh', 'vms', '--json');
    my @ips;

    if ($rc == 0) {
      my $data = decode_json($out);
      if ($data->{Tables} && @{$data->{Tables}} && $data->{Tables}[0]{Rows}) {
        my $ips_str = $data->{Tables}[0]{Rows}[0]{ips} || '';
        @ips = split(/,\s*/, $ips_str);
      }
    }

    info(
      "\n\n".
      "#M{$ENV{GENESIS_ENVIRONMENT}} Jumpbox deployed!\n\n".
      "For details about the deployment, run\n\n".
      "  #G{$ENV{GENESIS_CALL} info $ENV{GENESIS_ENVIRONMENT}}\n\n".
      "To access the jumpbox over SSH:\n\n".
      "  #G{$ENV{GENESIS_CALL} do $ENV{GENESIS_ENVIRONMENT} -- ssh}\n\n".
      "or:\n\n".
      (@ips ? "  #W{ssh $ips[0]}\n" : "")
    );
  }

  return $self->done(1);
}
# }}}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
