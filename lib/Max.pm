use strict;

package Max;
use IO::Socket::INET;
use IO::Select;
use Carp qw(croak carp);
use MIME::Base64 qw(decode_base64 encode_base64);
use Max::Room;
use Max::Device;

sub discover {
    my ($class) = @_;
    ref $class and croak "Class method called on instance";

    my $send = IO::Socket::INET->new(
        PeerAddr => "255.255.255.255",
        PeerPort => 23272,
        Proto => 'udp',
        Broadcast => 1,
        Reuse => 1,
    ) or die "Can't open broadcast socket ($!)";
    $send->send("eQ3Max*\0**********I") or die $!;

    my $receive = IO::Socket::INET->new(
        LocalAddr => "0.0.0.0",
        LocalPort => 23272,
        Proto => 'udp',
        Reuse => 1,
    );
    my $select = IO::Select->new;
    $select->add($receive);
    my $buf;
    if ($select->can_read(2) && $receive->recv($buf, 1)) {
        return $receive->peerhost;
    }
    return;
}

sub connect {
    my ($class, $host, $port) = @_;
    $port ||= 62910;
    my $self = bless {}, $class;

    $self->{sock} = IO::Socket::INET->new(
        PeerHost => $host, PeerPort => $port
    ) or die "Connect: $@";

    return $self;
}

sub _waitfor {
    my ($self, $prefix) = @_;

    while (my $line = $self->_readline) {
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

sub _send {
    my ($self, $prefix, $hexdata) = @_;
    $hexdata ||= "";
    $self->{sock}->print($prefix, encode_base64(pack "H*", $hexdata), "\r\n");
}

sub _readline {
    my ($self) = @_;
    return $self->{sock}->getline;
}

sub init {
    my ($self) = @_;

    my $devices = $self->{devices} ||= {};
    my $rooms   = $self->{rooms}   ||= {};

    LINE: while (my $line = $self->_readline) {
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
    $self->_send("n:");
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
    my ($self, $dev) = @_;
    $self->_send("t:01,1,", ref($dev) ? $dev->addr : $dev);
    $self->_waitfor("A");
}

sub disconnect {
    my ($self) = @_;
    $self->_send("q:");
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
    $room += 0;
    return $self->{rooms}{$room} ||= Max::Room->new(max => $self, id => $room);
}

1;
