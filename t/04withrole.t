use strict;
use warnings;
use Test::More;

{
	package Foo;
	
	use Moose::Role;
	use MooseX::CustomInitArgs;
	
	has foo => (
		is        => 'ro',
		traits    => [CustomInitArgs],
		init_args => ['fu', 'comfute' => sub { $_ }],
	);
}

{
	package Bar;
	use Moose;
	with 'Foo';
	has bar => (is => 'ro');
}

sub check ($$)
{
	my ($args, $name) = @_;
	is(Bar->new(@$args)->foo, 42, "$name");
}

check [foo     => 42], 'mutable class; standard init arg';
check [fu      => 42], 'mutable class; alternative init arg';
check [comfute => 42], 'mutable class; alternative init arg (with coderef)';

Bar->meta->make_immutable;

check [foo     => 42], 'immutable subclass; standard init arg';
check [fu      => 42], 'immutable subclass; alternative init arg';
check [comfute => 42], 'immutable subclass; alternative init arg (with coderef)';

done_testing;
