luvit-irc
=========
IRC client module for luvit

Documentation
-------------
See test.lua for more information

Example
-------
	local host = "ip-of-irc-server"
	local c = require ('irc').new ()
	c:connect (host, 6667, "botnick")
	c:on ("connect", function (x)
		c:privmsg ("yournick", "hello world")
		c:quit ()
	end)
	c:on ("quit", function ()
		process.exit (0)
	end)
