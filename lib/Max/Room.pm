use strict;

package Max::Room;
use Carp qw(croak carp);
use MIME::Base64 qw(decode_base64 encode_base64);

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

sub id { shift->{id} }
sub addr { shift->{addr} // "\0\0\0" }

sub name { 
    my ($self, $new) = @_;
    return $self->{name} if not defined $new;
    return $self->{name} = $new;
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
    my ($self, $new) = @_;

    return $self->_get_setpoint if not defined $new;

    my $t2 = $new * 2;
    ($t2 == int $t2) or croak "Temperature not a multiple of 0.5";
    $t2 > 0 or $t2 < 256 or croak "Invalid temperature ($new)";

    $self->{max}->_send("s:", sprintf "000440000000000000%02x%02x",
        $self->id,
        $t2 | 0x40,
    );
}

sub too_cold {
    my ($self, $maxdelta) = @_;
    $maxdelta ||= 0;

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
