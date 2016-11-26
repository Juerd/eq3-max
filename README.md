# Yet another

Because other implementations were part of larger systems, didn't compile, or
were incomplete to the point of being useless, eventually I decided to roll my
own. And of course, my version is incomplete too. But at least it's not part
of a larger system; just run the application and it should Just Work.

I've never used the official Windows or Mac software on my Cube, and as such
had to find out how to use the protocol from scratch. No portal, no cloud!
Just control the entire device from a single command line utility.

# Disclaimer

THIS SOFTWARE MAY OR MAY NOT WORK FOR YOUR USE CASE. IT WAS WRITTEN FOR MY
SPECIFIC SITUATION. DON'T COMPLAIN IF IT BURNS DOWN YOUR HOUSE...

I had to make a lot of assumptions. For example, I'll assume that all the
devices in a room should be linked together. But I only have at most 1 wall
thermostat and 1 TRV per room, so with multiple TRVs I don't know if my
assumption is correct.

Patches welcome, though! :-)
Please add detailed info about why the change was needed.

# How to use

Assuming out-of-the box Cube:

1. Get a debug dump to see if anything works at all. You should
see your Cube's serial number and RF address:

  ```
    ./max.pl dump
```

  If it cannot find your Max! Cube via UDP, you can set the `MAX_HOST`
  environment variable. If discovery does work, you may want to set the
  variable anyway, because that will make every call half a second faster.

  ```
    export MAX_HOST=192.168.1.9
    ./max.pl dump
```

2. Pair all the devices in a room. Pick a room number; in this example "2"
is the room ID. It might be useful to pick different room numbers than
your neighbours :)

  ```
    ./max.pl pair 2  # follow instructions to add to room 2
    ./max.pl pair 2  # repeat until done
```

3. See if the devices show up in the overview:

  ```
    ./max.pl
```

4. If you added multiple devices, set up links between the devices in the
room:

  ```
    ./max.pl crosslink 2
```

5. Set the temperature of the room:

  ```
    ./max.pl set 2  21.5
```

6. See if the devices report the new setpoint:

  ```
    ./max.pl
    # It may take a while before devices synchronise
```

7. Repeat 2 thru 6 for other rooms.

8. Use 'watch' to get a live refreshing overview:

  ```
    watch ./max.pl
```


