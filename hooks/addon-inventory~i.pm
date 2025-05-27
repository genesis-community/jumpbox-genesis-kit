#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker
package Genesis::Hook::Addon::Jumpbox::Inventory v2.7.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20

use parent qw(Genesis::Hook::Addon);
use lib $ENV{GENESIS_LIB} // "$ENV{HOME}/.genesis/lib";

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
	my ($out, $rc, $err) = run({interactive => 1}, 'bosh run-errand inventory');

	if ($rc != 0) {
		bail("Failed to run the inventory errand: $err");
	}

	return $self->done();
}

1;
