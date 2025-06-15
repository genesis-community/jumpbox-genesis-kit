# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
package Genesis::Hook::PostDeploy::Jumpbox;

use v5.20;
use warnings;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook::PostDeploy);

use Genesis qw/describe run/;
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
    
    print "\n\n";
    describe("#M{$ENV{GENESIS_ENVIRONMENT}} Jumpbox deployed!");
    print "\n";
    print "For details about the deployment, run\n";
    print "\n";
    describe("  #G{$ENV{GENESIS_CALL} info $ENV{GENESIS_ENVIRONMENT}}");
    print "\n";
    print "To access the jumpbox over SSH:\n";
    print "\n";
    describe("  #G{$ENV{GENESIS_CALL} do $ENV{GENESIS_ENVIRONMENT} -- ssh}");
    print "\n";
    print "or:\n";
    print "\n";
    describe("  #W{ssh $ips[0]}") if @ips;
    print "\n";
  }
  
  return $self->done();
}
# }}}

1;
