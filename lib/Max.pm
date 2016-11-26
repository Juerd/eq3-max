use strict;

package Max;
use IO::Socket::IP;
use Carp qw(croak carp);
use MIME::Base64 qw(decode_base64 encode_base64);
use Max::Room;
use Max::Device;

sub connect {
    my ($class, $host, $port) = @_;
    $port ||= 62910;
    my $self = bless {}, $class;
    $self->{sock} = IO::Socket::IP->new(
        PeerHost => $host, PeerPort => $port
    ) or die "Connect: $@";

    return $self;
}

sub _waitfor {
    my ($self, $prefix) = @_;
    my $sock = $self->{sock};
    WAIT: while (my $line = readline $sock) {
        if ($line =~ /^\Q$prefix\E:(.*)/) {
            return $1;
        } else {
            carp "Unexpected response: $line";
        }
    }
    carp "No response";
    return undef;
}

sub _command_success {
    my ($self) = @_;
    my $response = $self->_waitfor("S");
    my (undef, $error, undef) = split /,/, $response;
    return !$error;
}

sub _process_L {
    my ($self, $base64) = @_;
    my $data = decode_base64 $base64;
    my @devices = unpack "(C/a)*", $data;
    for my $devicedata (@devices) {
        my ($addr_bin, undef, $flags, $valve, $setpoint, $date, $time, $temp)
            = unpack "a3 C n C C n C C", $devicedata;

        my $addr = lc unpack "H*", $addr_bin;

        $temp |= !!($setpoint & 0x80) << 8;
        $setpoint &= 0x7F;

        my $device = $self->{devices}{$addr}
            or warn "Unexpected device $addr";

        $device->_set(
            flags => {
                init    => !! $flags & 0x0020,
                link    => !! $flags & 0x0040,
                battery => !! $flags & 0x0080,
                error   => !! $flags & 0x0800,
                invalid => !  $flags & 0x1000,
            },
            mode        => $flags & 0x0003,
            setpoint    => sprintf("%.1f", $setpoint / 2),
            temperature => sprintf("%.1f", $temp / 10),
            valve       => $valve,
        );
    }
}

sub init {
    my ($self) = @_;

    my $sock    = $self->{sock};
    my $devices = $self->{devices} ||= {};
    my $rooms   = $self->{rooms}   ||= {};

    LINE: while (my $line = readline $sock) {
        if ($line =~ /^C:([^,]+),(.*)/) {
            my ($addr, $data) = (lc $1, decode_base64 $2);
            my ($length, $addr2, $type, $room, $fw, $test, $serial)
                = unpack("C a3 C C C C a10", $data);

            $addr2 = lc unpack "H*", $addr2;

            warn "Address mismatch in 'C' response ($addr, $addr2)\n"
                if $addr ne $addr2;

            my $device = Max::Device->new(
                max         => $self,
                addr        => $addr2,
                type        => $type,
                firmware    => sprintf("%.1f", $fw/10),  # guessed
                test_result => $test,
                serial      => $serial,
            );

            $devices->{$addr} = $device;
            if ($room) {
                $rooms->{$room} ||= Max::Room->new(max => $self, id => $room);
                $rooms->{$room}->add_device($device);
                $device->_set(room => $rooms->{$room});
            }
        }
        if ($line =~ /^L:(.*)/) {
            $self->_process_L($1);
            last LINE;
        }
    }
    return $self;
}

sub pair {
    my ($self) = @_;
    $self->{sock}->print("n:\r\n");
    my $response = decode_base64 $self->_waitfor("N")
        or croak "No response";
    my ($type, $addr, $serial, $unknown) = unpack "C a3 a10 C", $response;

    $addr = lc unpack "H*", $addr;
    my $device = $self->{devices}{$addr} = Max::Device->new(
        max => $self,
        type => $type,
        addr => $addr,
        serial => $serial,
    );
    return $device;
}

sub forget {
    my ($self, $addr) = @_;
    my $base64 = encode_base64 pack "H*", $addr;
    $self->{sock}->print("t:01,1,$base64\r\n");
    $self->_waitfor("A");
}

sub disconnect {
    my ($self) = @_;
    $self->{sock}->print("q:\r\n");
    $self->{sock}->close;
}

sub devices {
    my ($self) = @_;
    return @{ $self->{devices} }{ sort keys %{$self->{devices}} };
}

sub rooms {
    my ($self) = @_;
    return @{ $self->{rooms} } { sort { $a<=>$b } keys %{$self->{rooms}} };
}

sub room {
    my ($self, $room) = @_;
    $room = $room->id if ref $room;
    $room += 0;
    return $self->{rooms}{$room} ||= Max::Room->new(max => $self, id => $room);
}

1;
