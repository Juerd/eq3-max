#!/usr/bin/perl -w
use strict;
use MIME::Base64;
use IO::Socket::IP;

my $host = "192.168.1.103";

{
    package Max::Device;
    use Carp qw(croak carp);
    use MIME::Base64 qw(decode_base64 encode_base64);

    my %modes = qw/0 auto 1 manual 2 vacation 3 boost/;
    my %types = qw/0 cube 1 heater 2 heater+ 3 thermostat 4 shutter 5 button/;

    sub new {
        my ($class, %p) = @_;
        return bless \%p, $class;
    }

    sub _set {
        my ($self, %p) = @_;
        @{ $self }{keys %p} = values %p;
    }

    sub addr        { shift->{addr} }
    sub room        { shift->{room} }
    sub setpoint    { shift->{setpoint} }
    sub valve       { shift->{valve} }
    sub temperature { shift->{temperature} }

    sub type_num {        shift->{type}  }
    sub type     { $types{shift->{type}} }
    sub mode_num {        shift->{mode}  }
    sub mode     { $modes{shift->{mode}} }

    sub flags_as_string {
        my ($self) = @_;
        return join " ", grep $self->{flags}{$_}, sort keys %{ shift->{flags} };
    }

    sub has_temperature { shift->{type} == 3 }
    sub has_valve       { shift->{type} == 1 or shift->{type} == 2 }
    sub is_cube         { shift->{type} == 0 }

    sub set_room {
        my ($self, $new) = @_;

        $self->{max}->{sock}->print("s:" .
            encode_base64(pack "H*", sprintf "000022000000$self->{addr}00%02x", $new)
            . "\r\n"
        );
        $self->{max}->_command_success("S") or return;

        my $room = $self->{max}->room($self->{room});
        $room->add_device($self);

        return $self->{room} = $room;
    }

    sub add_link {
        my ($self, $other) = @_;
        $self->{max}->{sock}->print("s:" . encode_base64(pack "H*", sprintf
            "000020000000$self->{addr}%02x%s%s",
            $other->room->id,
            $other->addr,
            $other->type_num,
        ) . "\r\n");
        return $self->{max}->_command_success("S");
    }
}

{
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
}

{
    package Max;
    use IO::Socket::IP;
    use Carp qw(croak carp);
    use MIME::Base64 qw(decode_base64 encode_base64);

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
                $rooms->{$room} ||= Max::Room->new(max => $self, id => $room);
                $rooms->{$room}->add_device($device);
                $device->_set(room => $rooms->{$room});
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
            type => $type, addr => $addr, serial => $serial
        );
        return $device;
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
        return if not exists $self->{rooms}{$room};
        return $self->{rooms}->{$room};
    }
}

sub _valid_uint8 {
    my ($id) = @_;
    defined $id     or return 0;
    $id += 0;
    $id == int($id) or return 0;
    $id >= 0        or return 0;
    $id <= 255      or return 0;
    return 1;
}
sub _valid_temperature {
    my ($t) = @_;
    defined $t      or return 0;
    $t += 0;
    ($t * 2) == int($t * 2) or return 0;
    $t >= 0 or return 0;  # limit?
    $t < 60 or return 0;  # limit?
    return 1;
}

my $command = shift || '';

if ($command eq 'pair') {
    my $usage = "Usage: $0 pair <roomid>\n";
    my $room = shift;
    _valid_uint8($room) && $room > 0 or die $usage;

    my $max = Max->connect($host)->init;
    print "Press and hold OK/Boost on the new device...\n";
    my $device = $max->pair();
    my $success = $device->set_room($room);
    print $success ? "Pairing succesful.\n" : "Pairing failed.\n";
} elsif ($command eq 'crosslink') {
    my $usage = "Usage: $0 crosslink <roomid>\n";
    my $room_id = shift;
    _valid_uint8($room_id) && $room_id > 0 or die $usage;

    my $max = Max->connect($host)->init;
    my $room = $max->room($room_id) or die "There is no room $room_id";
    my @devices = $room->devices or die "No devices in room $room_id";

    $| = 1;
    for my $dev (@devices) {
        my @others = grep $_->addr ne $dev->addr, @devices;
        for my $other (@others) {
            printf(
                "Telling %s %s about %s %s...",
                $dev->type, $dev->addr,
                $other->type, $other->addr
            );
            my $success = $dev->add_link($other);
            print $success ? " OK.\n" : " FAILED.\n";
        }
    }
} elsif ($command eq 'dump') {
    use Data::Dumper ();
    my $max = Max->connect($host)->init;
    print Data::Dumper::Dumper($max);
} elsif ($command eq 'set') {
    my $usage = "Usage: $0 manual <roomid> <temperature per 0.5>\n";
    my $room_id = shift;
    my $setpoint = shift;
    _valid_uint8($room_id) && $room_id > 0 or die $usage;
    _valid_temperature($setpoint) or die $usage;

    my $max = Max->connect($host)->init;
    my $room = $max->room($room_id) or die "There is no room $room_id";
    $room->set_temperature($setpoint) or die "Setting temperature failed";
} else {
    my $max = Max->connect($host)->init;
    for my $room ($max->rooms) {
        my @devices = $room->devices;
        next if @devices == 1 and $devices[0]->is_cube;

        printf "[Room %d]\n", $room->id;
        for my $device (@devices) {
            my $extra = 
                $device->has_temperature
                ? sprintf("(current %.1f) ", $device->temperature)
                : $device->has_valve
                ? sprintf("(valve at %d%%) ", $device->valve)
                : "";

            printf(
                "    %-10s %s: %s\@%.1f %s%s\n",
                $device->type,
                $device->addr,
                $device->mode,
                $device->setpoint,
                $extra,
                uc $device->flags_as_string,
            );
        }
    }
}

print "-Done-\n";
