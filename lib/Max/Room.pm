use strict;

package Max::Room;
use Carp qw(croak carp);
use MIME::Base64 qw(decode_base64 encode_base64);

my $defmode;
$defmode = $ENV{MAX_DEFMODE};
if(!defined $defmode || length($defmode) == 0)
{
    # MAX_DEFMODE is unset so hardcode value
    # Set Mode 00=auto, 01=manual, 10=vacation, 11=boost
    $defmode = "00";
}

sub new {
    my ($class, %p) = @_;
    $p{devices} ||= {};
    $p{id} or croak "id is mandatory";
    return bless \%p, $class;
}

sub _set {
    my ($self, %p) = @_;
    @{ $self }{keys %p} = values %p;
}

sub _send_radio {
    my ($self, $command, $hexdata) = @_;

    return $self->{max}->_send_radio($command, $hexdata, room => $self->id);
}

sub id { shift->{id} }
sub addr { shift->{addr} // "\0\0\0" }

sub name {
    my ($self, $new) = @_;
    return $self->{name} if not defined $new;
    return $self->{name} = $new;
}

sub display_name {
    my ($self, $include_id) = @_;
    if (defined $self->{name} and length $self->{name}) {
        return "$self->{name}($self->{id})" if $include_id;
        return $self->{name};
    }
    return "room " . $self->{id};
}

sub devices {
    my ($self) = @_;
    return @{ $self->{devices} }{ sort keys %{$self->{devices}} };
}

sub temperature {
    my ($self) = @_;

    for my $device ($self->devices) {
        return $device->temperature if $device->has_temperature;
    }
    return undef;
}

sub _get_setpoint {
    my ($self) = @_;

    for my $device ($self->devices) {
        # Favour wall thermostat over other devices
        return $device->setpoint if $device->has_temperature;
    }

    for my $device ($self->devices) {
        # TRVs sometimes report setpoint as 0.0
        return $device->setpoint if $device->setpoint > 0;
    }
    return undef;
}

sub setpoint {
    my ($self, $new, $setmode) = @_;

    return $self->_get_setpoint if not defined $new;

    my $t2 = $new * 2;
    ($t2 == int $t2) or croak "Temperature not a multiple of 0.5";
    $t2 > 0 or $t2 < 256 or croak "Invalid temperature ($new)";
    # Set Mode 00=auto, 01=manual, 10=vacation, 11=boost
    my $tempmode;
    if(!defined $setmode || length($setmode) == 0)
    {
    $tempmode = $defmode;
    } else {
    $tempmode = $setmode;
    }
    if ( $setmode eq '00' || lc($setmode) eq 'auto' ) {
    	$tempmode = '00';
    } elsif ( $setmode eq '01' || lc($setmode) eq 'manual' || lc($setmode) eq 'party' ) {
    	$tempmode = '01';
    } elsif ( $setmode eq '10' || lc($setmode) eq 'vacation' ) {
    	$tempmode = '10';
    } elsif ( $setmode eq '11' || lc($setmode) eq 'boost' ) {
    	$tempmode = '11';
    } else {
        $tempmode = $defmode;
    }


    # Calc Temperature
    my $tempbin = sprintf("%06b",$t2);
    # Combine Mode & Temperature to hex
    my $tempsendhex = sprintf('%02x', oct("0b$tempmode$tempbin"));
    # Send combined hex 
    return $self->_send_radio(0x40, $tempsendhex);
}

sub too_cold {
    my ($self, $maxdelta) = @_;
    $maxdelta ||= 0;

    return 1 if grep $_->mode eq 'boost', grep $_->has_setpoint, $self->devices;

    my $temperature = $self->temperature or return undef;
    my $setpoint = $self->setpoint or return undef;

    return $setpoint - $temperature > $maxdelta;
}

sub add_device {
    my ($self, $device) = @_;
    $device->isa("Max::Device") or croak "Not a Max::Device";
    $self->{devices}{ $device->addr } = $device;
}

1;
