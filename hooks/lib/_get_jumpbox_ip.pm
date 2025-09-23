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

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
