<img alt="Screencast of setting temperatures" src="screencast.svg">

# Yet another

In general, reinventing the wheel seems like a waste of time. But I decided to
roll my own anyway. The official software is closed source, requires an account,
and only runs on Microsoft Windows. Most open source Max! projects are very
incomplete, but all the feature complete solutions are part of complicated home
automation systems (FHEM, openHAB, Node-RED). And because I never used the
original software, I needed something that will even work if you begin with a
new, unconfigured Cube.

Of course, my program is incomplete too. It does exactly what I need, but not
much more. Note that it can work with readonly filesystems because the
configuration is taken from and written to the eQ-3 Max! system itself.

# Features

Ease of use:

* No "portal" account or any other cloud service needed.
* Works on new Max! Cubes out of the box.
* Works on most Linux systems without installing additional software.
* No configuration is needed, it can find the Cube automatically.
* All features can be used on the command line (beginner friendly).
* All features can be used via the Perl module (for advanced users).

Supported actions:

* Pairing new devices, assigning room IDs.
* Assigning names to rooms and devices.
* Cross-linking devices within a room.
* Setting (overriding) the temperature in a room.
* Switching a boiler on/off via an external program.
* Text based short or detailed status overview.

Contrib scripts included:

* _max2graphite_ will dump room statistics to a Graphite server running on
  localhost.
* _set-gpio_ can be used to drive a GPIO pin (e.g. on a Raspberry Pi) to
  switch a boiler via a relay.
* _welterusten_ (Dutch for "good night!") is an example of scheduling with
  `at`, as an alternative to fixed time schedules.

# Reference documentation

- [executable `max`](bin/max.pod)
- [Perl class `Max`](lib/Max.pod)
- [Perl class `Max::Device`](lib/Max/Device.pod)
- [Perl class `Max::Room`](lib/Max/Room.pod)

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
    max status
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
    max status
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

# Disclaimer

THIS SOFTWARE MAY OR MAY NOT WORK FOR YOUR USE CASE. IT WAS WRITTEN FOR MY
SPECIFIC SITUATION, BUT I HOPE IT'S USEFUL FOR YOURS. JUST DON'T COMPLAIN IF IT
BURNS DOWN YOUR HOUSE...

Because I don't have all the different devices in the eQ-3 Max! range, and the
vendor does not provide any official documentation, this software is based on a
lot of assumptions.

If you know Perl and have the Max! window switches or an "eco button", please
contribute patches.

# Does it work?

Please let me know. I'd love to receive a screenshot or copy/paste of `max
status` on your system.

# See also

* [eQ-3 Max! protocol documentation](https://github.com/Bouni/max-cube-protocol)

