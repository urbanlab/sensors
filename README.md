Sense
=====
version : 1.0.0

Manage a wireless sensor's network controlled by arduinos (called "multiplexers") publishing informations with XBees. It is configured via Redis.

Each arduino can handle multiple sensors.

The arduinos send via the xbees the informations to xbees receivers.

Each xbee receiver has one daemon managing it.

Daemons can be organized in different network id to organize this. (you can have more than one daemon in each network)

Clients control daemons via Redis and read informations via Redis.

More details : [wiki](http://doku.erasme.org/doku.php?id=projets:sense:start)

Executables
-----------
 - `bin/sense-daemon` interface between the sensors and the clients (try `./sense-daemon --help`)
 - `bin/cli controls` the daemons (`try ./cli --help`)
 - `bin/example-client` display values published (usage described inside)
 - `bin/xbee-setup` is a basic configurator for the xbees. Use it when arduinos fail at sending messages (they can't configure it when baudrate is bad)
 
Library
-------
 - Module `Sense` contains the whole library
 - `Sense::Common` contains general methods to interface with the network
 - `Sense::Client` contains an interface to redis to implement a client
 - `Sense::Daemon` contains an interface to redis to implement a daemon
 - `Sense::Serial` contains an interface to the Serial Port where the xbee receiver is plugged
 - `Sense::Shell` is called by cli to produce an interactive shell

Arduino
-------
The folder "firmware" contains code of the firmware that must be load into each multiplexer.

Configuration
-------------
The folder "conf" contains example config and profiles.
