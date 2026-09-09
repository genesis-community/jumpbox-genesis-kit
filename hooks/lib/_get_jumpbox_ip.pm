use Genesis qw/bail read_json_from/;

sub _get_jumpbox_ip {
	my ($self) = @_;

	# Get jumpbox IP
	my ($data, $rc) = read_json_from($self->env->bosh->execute('vms', '--json'));
	if ($rc == 0) {
		if ($data->{Tables} && @{$data->{Tables}} && $data->{Tables}[0]{Rows}) {
			my $ips = $data->{Tables}[0]{Rows}[0]{ips} || '';
			my @ips = split(/,\s*/, $ips);
			return $ips[0] if @ips;
		}
	}
	bail("Could not determine jumpbox IP address");
}

# Returns the SSH login target for the jumpbox as user@ip. The user comes from
# GENESIS_JUMPBOX_USER when set, otherwise the first account in params.users,
# and falls back to the bare IP when the env defines no accounts.
sub _get_jumpbox_login {
	my ($self) = @_;
	my $ip = $self->_get_jumpbox_ip();
	my $user = $ENV{GENESIS_JUMPBOX_USER};
	unless ($user) {
		my $users = $self->env->lookup('params.users', []);
		$user = $users->[0]{name} if ref($users) eq 'ARRAY' && @$users && ref($users->[0]) eq 'HASH';
	}
	return $user ? "$user\@$ip" : $ip;
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
