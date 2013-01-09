package MooseX::CustomInitArgs;

our $AUTHORITY = 'cpan:TOBYINK';
our $VERSION   = '0.001';

use 5.008;
use strict;
use warnings;
use Moose::Exporter;

use constant _AttrTrait => do
{
	package MooseX::CustomInitArgs::Trait::Attribute;
	our $AUTHORITY = 'cpan:TOBYINK';
	our $VERSION   = '0.001';
	
	use Moose::Role;
	use Moose::Util::TypeConstraints;
	use B 'perlstring';
	
	subtype 'OptList', as 'ArrayRef[ArrayRef]';
	coerce 'OptList',
		from 'ArrayRef' => via {
			require Data::OptList;
			Data::OptList::mkopt $_;
		},
		from 'HashRef' => via {
			my $hash = $_;
			[ map { [ $_ => $hash->{$_} ] } sort keys %$hash ];
		};
	
	has init_args => (
		is        => 'ro',
		isa       => 'OptList',
		predicate => 'has_init_args',
		coerce    => 1,
	);
	
	has _init_args_hashref => (
		is        => 'ro',
		isa       => 'HashRef',
		lazy      => 1,
		default   => sub {
			my $self = shift;
			+{ map { ;$_->[0] => $_->[1] } @{$self->init_args} };
		},
	);
	
	around new => sub
	{
		my $orig  = shift;
		my $class = shift;
		my $self  = $class->$orig(@_);
		
		if ($self->has_init_args and not $self->has_init_arg)
		{
			confess "Attribute ${\$self->name} defined with init_args but no init_arg";
		}
		
		return $self;
	};
	
	sub _inline_param_negotiation
	{
		my ($self, $param) = @_;
		my $init = $self->init_arg;
		
		my $regex        = join '|', map quotemeta, $self->init_arg, map $_->[0], @{$self->init_args||[]};
		my $with_coderef = join '|', map quotemeta, map $_->[0], grep {  defined($_->[1]) } @{$self->init_args||[]};
		my $no_coderef   = join '|', map quotemeta, map $_->[0], grep { !defined($_->[1]) } @{$self->init_args||[]};
		
		return (
			"if (my \@supplied = grep /^(?:$regex)\$/, keys \%${param}) {",
			'  if (@supplied > 1) {',
			'    Carp::confess("Conflicting init_args (@{[join q(, ), sort @supplied]})");',
			'  }',
			"  elsif (grep /^(?:$no_coderef)\$/, \@supplied) { ",
			"    ${param}->{${\perlstring $self->init_arg}} = delete ${param}->{\$supplied[0]};",
			"  }",
			"  elsif (grep /^($with_coderef)\$/, \@supplied) { ",
			"    local \$_ = delete ${param}->{\$supplied[0]};",
			"    ${param}->{${\perlstring $self->init_arg}} = \$MxCIA_attrs{${\$self->name}}->_run_init_coderef(\$supplied[0], \$class, \$_);",
			"  }",
			"}",
		);
	}
	
	sub _run_init_coderef
	{
		my ($self, $arg, $class, $value) = @_;
		
		my $code = $self->_init_args_hashref->{$arg};
		ref $code eq 'SCALAR' and $code = $$code;
		
		$class->$code($value);
	}
	
	around initialize_instance_slot => sub
	{
		my $orig = shift;
		my $self = shift;
		my ($meta_instance, $instance, $params) = @_;
		
		$self->has_init_args
			or return $self->$orig(@_);
		
		my @supplied = grep { exists $params->{$_->[0]} } @{$self->init_args}
			or return $self->$orig(@_);
		
		if (exists $params->{$self->init_arg})
		{
			push @supplied, [ $self->init_arg => undef ];
		}
		
		if (@supplied > 1)
		{
			confess sprintf(
				'Conflicting init_args (%s)',
				join(', ', sort map $_->[0], @supplied)
			);
		}
		
		if (my $code = $supplied[0][1])
		{
			ref $code eq 'SCALAR' and $code = $$code;
			
			local $_ = delete $params->{ $supplied[0][0] };
			$self->_set_initial_slot_value(
				$meta_instance, 
				$instance, 
				$instance->$code($_),
			);
		}
		else
		{
			$self->_set_initial_slot_value(
				$meta_instance, 
				$instance, 
				delete $params->{$supplied[0][0]},
			);
		}
		
		return;
	};
	
	__PACKAGE__;
};

use constant _ClassTrait => do
{
	package MooseX::CustomInitArgs::Trait::Class;
	our $AUTHORITY = 'cpan:TOBYINK';
	our $VERSION   = '0.001';
	
	use Moose::Role;
	
	has _mxcia_hash => (
		is      => 'ro',
		isa     => 'HashRef',
		lazy    => 1,
		builder => '_build__mxcia_hash',
	);
	
	sub _build__mxcia_hash
	{
		my $self = shift;
		return +{
			map  { ;$_->name => $_ }
			grep { ;$_->can('does') && $_->does(MooseX::CustomInitArgs::_AttrTrait) }
			$self->get_all_attributes
		};
	}
	
	around _eval_environment => sub
	{
		my $orig = shift;
		my $self = shift;
		my $eval = $self->$orig(@_);
		$eval->{'%MxCIA_attrs'} = $self->_mxcia_hash;
		return $eval;
	};
	
	around _inline_slot_initializer => sub
	{
		my $orig = shift;
		my $self = shift;
		my ($attr, $idx) = @_;
		
		return $self->$orig(@_)
			unless $attr->can('does')
			&&     $attr->does(MooseX::CustomInitArgs::_AttrTrait)
			&&     $attr->has_init_args;
		
		return (
			$attr->_inline_param_negotiation('$params'),
			$self->$orig(@_),
		);
	};
	
	__PACKAGE__;
};

use constant _ApplicationToClassTrait => do
{
	package MooseX::CustomInitArgs::Trait::Application::ToClass;
	our $AUTHORITY = 'cpan:TOBYINK';
	our $VERSION   = '0.001';
	
	use Moose::Role;

	around apply => sub
	{
		my $orig = shift;
		my $self = shift;
		my ($role, $class) = @_;
		$class = Moose::Util::MetaRole::apply_metaroles(
			for             => $class->name,
			class_metaroles => {
				class => [MooseX::CustomInitArgs::_ClassTrait],
			},
		);
		$self->$orig($role, $class);
	};
	
	__PACKAGE__;
};

Moose::Exporter->setup_import_methods(
	class_metaroles => {
		class     => [ _ClassTrait ],
		attribute => [ _AttrTrait ],
	},
	role_metaroles => {
		application_to_class => [ _ApplicationToClassTrait ],
		applied_attribute    => [ _AttrTrait ],
	},
);

1;

__END__

=head1 NAME

MooseX::CustomInitArgs - define multiple init args with custom processing

=head1 SYNOPSIS

   package Circle {
      use Moose;
      use MooseX::CustomInitArgs;
      
      has radius => (
         is        => 'ro',
         isa       => 'Num',
         required  => 1,
         init_args => [
            r        => undef,
            diameter => sub { $_ / 2 },
         ],
      );
   }
   
   # All three are equivalent...
   my $circle = Circle->new(radius => 1);
   my $circle = Circle->new(r => 1);
   my $circle = Circle->new(diameter => 2);

=head1 DESCRIPTION



=head1 BUGS

Please report any bugs to
L<http://rt.cpan.org/Dist/Display.html?Queue=MooseX-CustomInitArgs>.

=head1 SEE ALSO

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2013 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

