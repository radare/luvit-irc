luvit-irc
=========
IRC client module for luvit
Features:
* SSL Support
* SASL Support

Documentation
-------------
See test.lua for more information

TODO
----
* Modularize server handlers

Example
-------
	local host = "irc-server-address"
	local c = require ('irc').new ()
	c:connect (host, 6667, "botnick")
	c:on ("connect", function (x)
		c:privmsg ("yournick", "hello world")
		c:quit ()
	end)
	c:on ("quit", function ()
		process.exit (0)
	end)
