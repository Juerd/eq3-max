# Yet another

Because other implementations were part of larger systems, didn't compile, or
were incomplete to the point of being useless, eventually I decided to roll my
own. And of course, my version is incomplete too. But it's a stand-alone script
that does not depend on an entire home automation platform.

I've never used the official Windows or Mac software on my Cube, and as such
had to find out how to use the protocol on a new, unconfigured Cube. No portal,
no cloud! Just control the entire device from a single command line utility.

# Disclaimer

THIS SOFTWARE MAY OR MAY NOT WORK FOR YOUR USE CASE. IT WAS WRITTEN FOR MY
SPECIFIC SITUATION. DON'T COMPLAIN IF IT BURNS DOWN YOUR HOUSE...

I had to make a lot of assumptions. For example, I'll assume that all the
devices in a room should be linked together. But I only have at most 1 wall
thermostat and 1 TRV per room, so with multiple TRVs I don't know if my
assumption is correct. And I have no idea how the Eco button works, or whether
the program will work with other "eQ-3 Max!" devices that I don't own.

Patches welcome, though! :-)
Please add detailed info about why the change was needed.

# Installing

## Prerequisites on a normal Linux system

All regular Linux distributions come with Perl and Perl modules pre-installed.

## Prerequisites on an OpenWRT system

To run this program on a router running OpenWRT, install perl and its core
modules:

```
    opkg update
    opkg install perl perlbase-essential perlbase-config perlbase-cwd \
        perlbase-findbin perlbase-io perlbase-list perlbase-mime \
        perlbase-socket
```

## Installation

This repository comes without an installer and installation is not necessary
because you can run it from the repository.

But you could do something like:

```
    git clone git://github.com/Juerd/eq3-max /opt/eq3-max
    ln -s /opt/eq3-max/bin/* /usr/local/bin
```

# How to use

Assuming out-of-the box Cube:

1. Get a debug dump to see if anything works at all. You should
see your Cube's serial number and RF address:

  ```
    max dump
```

  If it cannot find your Max! Cube via UDP, you can set the `MAX_HOST`
  environment variable. If discovery does work, you may want to set the
  variable anyway, because that will make every call half a second faster.

  ```
    export MAX_HOST=192.168.1.9
    max dump
```

2. Pair all the devices in a room. Pick a room number; in this example "2"
is the room ID. It might be useful to pick different room numbers than
your neighbours :)

  ```
    max pair 2  # follow instructions to add to room 2
    max pair 2  # repeat until done
```

3. See if the devices show up in the overview:

  ```
    max
```

4. If you added multiple devices, set up links between the devices in the
room:

  ```
    max crosslink 2
```

5. Set the temperature of the room:

  ```
    max set 2  21.5
```

6. See if the devices report the new setpoint:

  ```
    max
    # It may take a while before devices synchronise
```

7. Repeat 2 thru 6 for other rooms.

8. Use 'watch' to get a live refreshing overview:

  ```
    watch max
```

Optionally, configure names for your rooms and devices:

```
    max name 2 "living room"
    max name 123abc "radiator south"
    max name 123def "radiator west"
    max name 3 "master bedroom"
    max name 4 "kitchen"
    # etc...
```

You could store this as a script, in case you ever have to do it again.

# Controlling a boiler for central heating

You may skip this part if you don't have a boiler that needs to be switched.

The Max! system by itself is not suited for use with a boiler that requires
a single thermostat to indicate the demand for heating. The `max switch`
command can emulate a simple thermostat and will execute a given command:

```
    max switch '/opt/eq3-max/contrib/set-gpio'
```

This example will call the ```set-gpio``` script with a single parameter
(`0` or `1`) to control a relay.

Additional parameters can be specified if you need other values than `0` and
`1`, and the command may include `%s` to indicate an alternative location
for the variable:

```
    max switch '/usr/local/bin/%s-my-boiler' enable disable
```

This will run either `enable-my-boiler` or `disable-my-boiler`.

- `max switch` needs to be called frequently, for example once every 10 seconds.
- The program is stateless and will unconditionally execute the given command,
  even if no change has occurred.
- It will only request heat if any room with a wall thermostat is too cold AND
  at least one TRV has a valve that is sufficiently opened. As such, it may
  take a minute after setting a new temperature setpoint, before the heater will
  come on.

For a dry-run test, use `max switch echo`.

# Does it work?

Please let me know. :-)

