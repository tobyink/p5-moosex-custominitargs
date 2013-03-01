use strict;
use warnings;
use Test::More tests => 2;

my $XXX;

{	
	package XXX;
	
	use Moose;
	use Moose::Util::TypeConstraints;
	use MooseX::CustomInitArgs;
	
	subtype 'MyArrayRef', as 'ArrayRef';
	coerce 'MyArrayRef', from 'Any', via { [$_] };
	
	has xxx => (
		is        => 'ro',
		isa       => 'MyArrayRef',
		coerce    => 1,
		init_args => [
			_xxx => sub { $XXX = $_ },
		],
	);
}

for my $i (666 .. 667)
{
	XXX->new( _xxx => $i );

	is_deeply(
		$XXX,
		[ $i ],
		'coercion happens before init_args coderefs get called',
	);

	XXX->meta->make_immutable;
}
