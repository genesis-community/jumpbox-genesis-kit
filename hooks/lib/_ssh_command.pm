# Helpers shared by the ssh and who addons for turning the arguments an addon
# receives into the argument vector we hand to ssh.
#
# Genesis strips the separator that divides its own options from the addon's,
# so `genesis <env> do -- ssh -- uptime -p` reaches the addon as the list
# ('--', 'uptime', '-p'). Everything before that remaining separator is an
# option for ssh itself, and everything after it is the command to run on the
# jumpbox. We quote that command ourselves and pass it as a single argument,
# because ssh otherwise joins the words it is given with spaces and the remote
# shell resplits them.
#
# This mixin deliberately does not load Genesis, so the spec suite can exercise
# it on its own.

# _split_ssh_args - divide addon arguments into ssh options and a remote command {{{
sub _split_ssh_args {
	my ($self, @args) = @_;
	my (@opts, @cmd);

	while (@args) {
		my $arg = shift @args;
		unless ($arg eq '--') {
			push @opts, $arg;
			next;
		}
		# Collapse a run of separators so that `-- --` means the same as `--`.
		shift @args while @args && $args[0] eq '--';
		@cmd = @args;
		last;
	}

	return (\@opts, \@cmd);
}
# }}}

# _shell_quote - quote a single argument for the remote shell {{{
sub _shell_quote {
	my ($self, $arg) = @_;
	return "''" unless defined($arg) && length($arg);
	return $arg if $arg =~ m{^[A-Za-z0-9_\@%+=:,./-]+$};
	$arg =~ s/'/'\\''/g;
	return "'$arg'";
}
# }}}

# _remote_command - join arguments into one safely quoted command string {{{
sub _remote_command {
	my ($self, @args) = @_;
	return join(' ', map {$self->_shell_quote($_)} @args);
}
# }}}

# _ssh_command - build the full argument vector to exec {{{
# Takes the ssh login target, the addon's arguments, and any words that always
# lead the remote command (the who addon always runs `who`). Returns a list
# suitable for exec, ending in the quoted remote command when there is one.
sub _ssh_command {
	my ($self, $target, $args, @prefix) = @_;
	my ($opts, $cmd) = $self->_split_ssh_args(@{$args || []});
	my @remote = (@prefix, @$cmd);
	my @ssh = ('ssh', @$opts, $target);
	# The separator keeps ssh from reading a command that starts with a dash as
	# one of its own options. Without it, ssh swallows the command and opens an
	# interactive shell instead.
	push @ssh, '--', $self->_remote_command(@remote) if @remote;
	return @ssh;
}
# }}}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
