#!/usr/bin/perl -w
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

sub id { shift->{id} };

sub devices {
    my ($self) = @_;
    return @{ $self->{devices} }{ sort keys %{$self->{devices}} };
}

sub add_device {
    my ($self, $device) = @_;
    $device->isa("Max::Device") or croak "Not a Max::Device";
    $self->{devices}{ $device->addr } = $device;
}

sub set_temperature {
    my ($self, $temperature) = @_;
    my $t2 = $temperature * 2;
    ($t2 == int $t2) or croak "Temperature not a multiple of 0.5";
    $t2 > 0 or $t2 < 256 or croak "Invalid temperature ($temperature)";

    $self->{max}->{sock}->print("s:" . encode_base64(pack "H*", sprintf
        "000440000000000000%02x%02x",
        $self->id,
        $t2 | 0x40,
    ) . "\r\n");
}

1;
