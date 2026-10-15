# Shared vault existence check, included into hook packages via:
#   do <hooks-dir>/lib/_vault_exists.pm
#
# `safe exists` exits 1 both when a secret is absent and when the vault cannot
# be reached, is sealed, or rejects the token. With --quiet the absent case
# prints nothing, while every failure prints a "!! ..." line on stderr. This
# helper keeps the two apart so that a vault error is never read as "missing".

use Genesis qw/bail run/;

# _vault_has - true when the secret (or secret:key) exists, false when it is
# missing, and a bail for any other outcome. {{{
sub _vault_has {
	my ($self, $ref) = @_;
	my (undef, $rc, $err) = run({stderr => 0}, 'safe --quiet exists "$1"', $ref);
	return 1 if $rc == 0;

	$err = defined($err) ? $err : '';
	$err =~ s/^\s+|\s+$//g;
	return 0 if $rc == 1 && $err eq '';

	bail(
		"Cannot tell whether %s exists in vault (safe exited %s): %s",
		$ref, $rc, length($err) ? $err : 'no output'
	);
}
# }}}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
