package Transform::Grep;
use Moose;
use Data::Dumper;
use CHI;
use AnyEvent::HTTP;
use Socket;
use JSON;
extends 'Transform';
our $Name = 'Grep';
has 'name' => (is => 'ro', isa => 'Str', required => 1, default => $Name);
has 'field' => (is => 'ro', isa => 'Ref', required => 1, default => sub { qr/./ });
has 'regex' => (is => 'ro', required => 1, default => sub { qr/./ });
has 'operator' => (is => 'ro', isa => 'Str');
our $Valid_operators = { map { $_ => 1 } qw(== != > >= < <=) };

sub BUILDARGS {
	my $class = shift;
	##my $params = $class->SUPER::BUILDARGS(@_);
	my %params = @_;
	$params{field} = qr/$params{args}->[0]/i if defined $params{args}->[0];
	if (defined $params{args}->[1] and defined $params{args}->[2] and $Valid_operators->{ $params{args}->[2] }){
		$params{regex} = $params{args}->[1];
		$params{operator} = $params{args}->[2];
	}
	else {
		$params{regex} = qr/$params{args}->[1]/i if defined $params{args}->[1];
	}
	return \%params;
}

sub BUILD {
	my $self = shift;
	$self->log->debug('field: ' . Dumper($self->field));
	$self->log->debug('regex: ' . Dumper($self->regex));
	#$self->log->debug('begin with data: ' . Dumper($self->data));
	
	DATUM_LOOP: foreach my $record ($self->results->all_results){
		foreach my $key ($self->results->keys($record)){
			next unless $key =~ $self->field;
			$self->_check($record, $self->results->value($record, $key)) and next DATUM_LOOP;
		}
		foreach my $transform (keys %{ $record->{transforms} }){
			next unless ref($record->{transforms}->{$transform}) eq 'HASH';
			foreach my $transform_field (keys %{ $record->{transforms}->{$transform} }){
				if (ref($record->{transforms}->{$transform}->{$transform_field}) eq 'HASH'){
					foreach my $key (keys %{ $record->{transforms}->{$transform}->{$transform_field} }){
						next unless "$transform.$transform_field.$key" =~ $self->field;
						#$self->log->trace('passed field ' . $transform_field . '.' . $key);
						if (ref($record->{transforms}->{$transform}->{$transform_field}->{$key}) eq 'ARRAY'){
							foreach my $value (@{ $record->{transforms}->{$transform}->{$transform_field}->{$key} }){
								$self->_check($record, $value) and next DATUM_LOOP;
							}
						}
						else {
							$self->_check($record, $record->{transforms}->{$transform}->{$transform_field}->{$key}) and next DATUM_LOOP;
						}
					}
				}
				elsif (ref($record->{transforms}->{$transform}->{$transform_field}) eq 'ARRAY'
					and $transform . '. ' . $transform_field =~ $self->field){
					#$self->log->trace('passed field ' . $transform_field);
					foreach my $value (@{ $record->{transforms}->{$transform}->{$transform_field} }){
						$self->_check($record, $value) and next DATUM_LOOP;	
					}
				}
			}
		}
	}

	foreach my $record ($self->results->all_results){
		if (exists $record->{transforms}->{$Name}){
			delete $record->{transforms}->{$Name}; # no need to clutter our final results
		}
		else {
			$self->results->delete_record($record);
		}
	}
	
	$self->log->debug('final data: ' . Dumper($self->results));
	
	$self->on_transform->($self->results);
	
	return $self;
}

sub _check {
	my $self = shift;
	my $record = shift;
	my $value = shift;
	
	if ($self->operator){
		my $test = $value . ' ' . $self->operator . ' ' . $self->regex;
		if (eval($test)){
			#$self->log->trace('passed value ' . $value);
			$record->{transforms}->{$Name} = '__KEEP__';
			return 1;
		}
	}
	elsif ($value =~ $self->regex){
		#$self->log->trace('passed value ' . $value);
		$record->{transforms}->{$Name} = '__KEEP__';
		return 1;
	}
	else {
		#$self->log->trace('FAIL value ' . $value);
	}
	return 0;
}
 
1;