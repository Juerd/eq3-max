use strict;

package Max;
use IO::Socket::INET;
use IO::Select;
use Carp qw(croak carp);
use MIME::Base64 qw(decode_base64 encode_base64);
use List::Util ();
use Max::Room;
use Max::Device;

sub _send_udp {
    my ($opcode, $host, $serial) = @_;
    $host ||= '255.255.255.255';  # broadcast
    $serial ||= '**********';     # matches any serial number

    my $send = IO::Socket::INET->new(
        PeerAddr => "255.255.255.255",
        PeerPort => 23272,
        Proto => 'udp',
        Broadcast => 1,
        Reuse => 1,
    ) or die "Can't open broadcast socket ($!)";

    $send->send("eQ3Max*\0$serial$opcode") or die $!;
}

sub discover {
    my ($class) = @_;
    ref $class and croak "Class method called on instance";

    _send_udp("I");

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
    my $self = bless { host => $host }, $class;

    $self->{sock} = IO::Socket::INET->new(
        PeerHost => $host, PeerPort => $port, Timeout => 5
    ) or die "Connect: $@";

    $self->_init;

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

sub _process_H {
    my ($self, $data) = @_;

    ($self->{serial}, $self->{addr}, $self->{firmware}) = split /,/, $data;

    # There's more in this header, but it's not very interesting:
    # unknown, "HTTP connection id", duty cycle, free memory slots,
    # date, time, state time, ntp counter.
}

sub _process_C {
    my ($self, $data) = @_;
    my ($addr_hex, $base64) = $data =~ /([^,]+),(.*)/;

    my ($length, $addr2, $type, $room, $fw, $test, $serial, $config)
        = unpack("C a3 C C C C a10 a*", decode_base64 $base64);

    my $addr2_hex = unpack "H*", $addr2;
    warn "Address mismatch in 'C' response ($addr_hex != $addr2_hex)\n"
        if $addr2_hex ne $addr_hex;

    my $device = Max::Device->new(
        max         => $self,
        addr        => $addr2,
        type        => $type,
        firmware    => sprintf("%.1f", $fw/10),  # guessed
        test_result => $test,
        serial      => $serial,
        config      => $config,
    );

    $self->{devices}{$addr2} = $device;
    if ($room) {
        my $rooms = $self->{rooms};

        $rooms->{$room} ||= Max::Room->new(max => $self, id => $room);
        $rooms->{$room}->add_device($device);
        $device->_set(room => $rooms->{$room});
    }
}

sub _process_L {
    my ($self, $base64) = @_;
    my $data = decode_base64 $base64;
    my @devices = unpack "(C/a)*", $data;
    for my $devicedata (@devices) {
        my ($addr, undef, $flags, $valve, $setpoint, $date, $time, $temp)
            = unpack "a3 C n C C n C C", $devicedata;

        my $device = $self->{devices}{$addr}
            or warn "Unexpected device " . unpack("H*", $addr);

        $device->_set(flags => {
            link_error    => !! ($flags & 0x0040),
            battery       => !! ($flags & 0x0080),
            uninitialized => !  ($flags & 0x0200),
            error         => !! ($flags & 0x0800),
            invalid       => !  ($flags & 0x1000),
        });

        if (defined $setpoint) {  # not for button/shutter
            $temp |= !!($setpoint & 0x80) << 8;
            $setpoint &= 0x7F;

            $temp = $date if $temp == 0 and $date > 0 and $device->has_temperature;

            $device->_set(
                mode        => $flags & 0x0003,
                setpoint    => $setpoint / 2,
                temperature => $temp / 10,
                valve       => $valve,
            );
        }
    }
}

sub _process_M {
    my ($self, $data) = @_;
    my ($i, $num, $base64) = $data =~ /([^,]+),([^,]+),(.*)/
        or return;

    my $md_tmp = $self->{metadata_tmp} ||= [];
    $md_tmp->[$i] = $base64;

    if (@$md_tmp == $num) {
        my $md = decode_base64 join "", @$md_tmp;
        @$md_tmp = ();

        $md =~ s/^V\x02// or croak "Unknown metadata version";
        my $roomcount = unpack "C", $md;
        my $offset = 1;
        my $rooms = 0;
        while ($rooms < $roomcount) {
            my ($id, $name, $addr) = unpack "C C/a a3", substr $md, $offset;

            $rooms++;
            $offset += 5 + length $name;

            $self->{rooms}{$id} ||= Max::Room->new(
                max  => $self,
                id   => $id,
                name => $name,
                addr => $addr
            );
        }

        my $devcount = unpack "C", substr $md, $offset;
        $offset++;
        my $devs = 0;
        while ($devs < $devcount) {
            my ($type, $addr, $serial, $name, $room_id)
                = unpack "C a3 a10 C/a C", substr $md, $offset;

            $devs++;
            $offset += 16 + length $name;

            # At this point, store just the name, because the rest comes from
            # the C and L messages, which are more authoritative.
            $self->{devicenames}{$addr} = $name;
        }
    }
}

sub _send {
    my ($self, $prefix, $hexdata) = @_;
    $hexdata ||= "";
    $self->{sock}->print($prefix, encode_base64(pack "H*", $hexdata), "\r\n");
}

sub _send_radio {
    my ($self, $command, $hexdata, %param) = @_;
    $param{device} or $param{room} or croak "no device or room in _send_radio";
    my $from  = delete $param{from}   // "000000";   # hex
    my $to    = delete $param{device} // "000000";   # hex
    my $room  = delete $param{room}   // 0;  # int

    $self->_send("s:", sprintf(
        "00%02x%02x%s%s%02x%s",
        $room && $to eq "000000" ? 4 : 0, $command, $from, $to, $room, $hexdata
    ));

    my $response = $self->_waitfor("S");
    my (undef, $error, undef) = split /,/, $response;
    return !$error;
}

sub _readline {
    my ($self) = @_;
    return $self->{sock}->getline;
}

sub _init {
    my ($self) = @_;

    $self->{devices} = {};
    $self->{rooms}   = {};

    while (my $line = $self->_readline) {
        $self->_process_H($1)       if $line =~ /^H:(.*)/;
        $self->_process_M($1)       if $line =~ /^M:(.*)/;
        $self->_process_C($1)       if $line =~ /^C:(.*)/;
        $self->_process_L($1), last if $line =~ /^L:(.*)/;
    }

    for my $device ($self->devices) {
        my $name = delete $self->{devicenames}{ $device->addr } or next;
        $device->name($name);
    }

    return $self;
}

sub pair {
    my ($self) = @_;
    $self->_send("n:");
    my $response = decode_base64 $self->_waitfor("N")
        or croak "No response";
    my ($type, $addr, $serial, $unknown) = unpack "C a3 a10 C", $response;

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

sub DESTROY {
    my ($self) = @_;
    $self->{sock} or return;
    $self->disconnect;
}

sub devices {
    my ($self) = @_;
    return @{ $self->{devices} }{ sort keys %{$self->{devices}} };
}

sub device {
    my ($self, $addr) = @_;
    $addr = pack "H*", $addr if length($addr) == 6;
    return undef if not exists $self->{devices}{$addr};
    return $self->{devices}{$addr};
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

sub write_metadata {
    my ($self) = @_;

    my @rooms = $self->rooms;
    my @devices = $self->devices;
    my $base64 = encode_base64(
        join("",
            "V\x02",  # Version?
            pack("C", scalar @rooms),
            map(pack(
                "C C/a a3",
                $_->id, $_->name // "", $_->addr
            ), @rooms),
            pack("C", scalar @devices),
            map(pack(
                "C a3 a10 C/a C",
                $_->type_num, $_->addr, $_->serial//"", $_->name//"",
                ($_->room ? $_->room->id : 0)
            ), @devices)
        ),
        ""
    );
    my @blocks = unpack "(a1900)*", $base64;
    for (my $i = 0; $i < @blocks; $i++) {
        $self->_send(sprintf "m:%02x,%s", $i, $blocks[$i]);
        $self->_waitfor("A");
    }
}

sub heat_demand {
    my ($self) = @_;
    my $demand = grep $_->too_cold, $self->rooms;
    my @valves = map $_->valve, grep $_->has_valve, $self->devices;

    $demand = 0 unless List::Util::sum(@valves) > 60
        or List::Util::max(@valves) > 50;

    return !!$demand;
}

sub reboot {
    my ($self) = @_;
    _send_udp("R", $self->{host}, $self->{serial});
}

1;
