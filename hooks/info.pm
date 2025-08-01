package Genesis::Hook::Info::Jumpbox;

use v5.20;
use warnings;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook);

use Genesis qw/info run read_json_from/;
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

  # Get jumpbox IP addresses
  my ($data, $rc) = read_json_from($self->env->bosh->execute('vms', '--json'));
  if ($rc == 0) {
    if ($data->{Tables} && @{$data->{Tables}} && $data->{Tables}[0]{Rows}) {
      my $ips = $data->{Tables}[0]{Rows}[0]{ips} || '';
      my @ips = split(/,\s*/, $ips);

      info("jumpbox ip(s): #C{" . join(' ', @ips) . "}\n");
    }
  } else {
    info("Error getting IP");
  }

  # TODO: List users and expiry of certs

  return $self->done();
}
# }}}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
