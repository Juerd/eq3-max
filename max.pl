#!/usr/bin/perl -w
use strict;
use lib 'lib';
use Max;

my $host = "192.168.1.103";

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
    print "Pairing done; setting room ID...\n";
    my $success = $device->set_room($room);
    print $success ? "Pairing succesful.\n" : "Pairing failed.\n";
} elsif ($command eq 'forget') {
    my $usage = "Usage: $0 forget <addr>\n";
    my ($addr) = (lc shift // "") =~ /^([0-9A-Fa-f]{6})$/ or die $usage;

    my $max = Max->connect($host)->init;
    $max->forget($addr);
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
