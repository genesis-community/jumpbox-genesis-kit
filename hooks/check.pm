#!/usr/bin/env perl
# vim: set ts=2 sw=2 sts=2 foldmethod=marker
package Genesis::Hook::Check::Jumpbox v2.7.0;

use strict;
use warnings;
use v5.20; # Genesis min perl version is 5.20

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook);

use Genesis qw/info bail/;

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0-rc.20');
	$obj->{ok} = 1; # Start assuming all checks will pass
	return $obj;
}

sub perform {
	my ($self) = @_;

	# Check users file if specified
	my $users_file = $self->env->lookup('params.users_file', '');
	if ($users_file) {
		if (!-f $self->env->path($users_file)) {
			info("Missing users file: '$users_file'");
			$self->{ok} = 0;
		}
	}

	# Return result
	if ($self->{ok}) {
		$self->env->notify(success => "environment files [#G{OK}]");
	} else {
		$self->env->notify(error => "environment files [#R{FAILED}]");
	}

	return $self->done($self->{ok});
}

1;
