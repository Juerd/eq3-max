use strict;

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

    $self->{max}->_send("s:", sprintf "000022000000$self->{addr}00%02x", $new);
    $self->{max}->_command_success("S") or return;
    $self->{room} = $new;

    my $room = $self->{max}->room($self->{room});
    $room->add_device($self);

    return $self->{room} = $room;
}

sub add_link {
    my ($self, $other) = @_;
    $self->{max}->_send("s:", sprintf "000020000000$self->{addr}%02x%s%s",
        $other->room->id,
        $other->addr,
        $other->type_num,
    );
    return $self->{max}->_command_success("S");
}

1;
