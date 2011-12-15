#!/usr/bin/env luvit
-- TODO: use getopt
-- TODO: support dns
-- TODO: use prompt and autocompletion

local IRC = require ('irc')

local host = "irc.freenode.net"
local port = 6667
local c = nil
local nick = "lubot3"

host = "94.125.182.252" -- freenode
-- host = "173.225.186.74" -- oftc
-- host = "194.149.75.80" -- hispano

local channel = ""

local c = IRC.new ()
c:on ("connect", function (x)
	if not x then
		print ("Cannot connect")
		process.exit (1)
	end
	p ("Connected")
end)
c:on ("error", function (x)
	p ("error")
	process.exit (1)
end)
c:on ("notice", function (host, msg)
	p ("NOTICE", host, msg)
end)
c:on ("data", function (x)
--		print ("::: "..x)
	end)
c:on ("join", function (x)
		print ("--> joined to channel "..x)
	end)
local execline = nil
local execerr = nil
function evalstr(x)
	local s = "local ret = ("..execline..")\n"..
	"if ret then return ''..(ret) else return nil end"
p("execline: ", s)
	execline, execerr = loadstring (s)
	if execline then
		execline = execline ()
	else
		execline = nil
	end
p("execline: ", execline)
end
c:on ("privmsg", function (user, msg)
		print ("<"..user.."> "..msg)
		if msg:sub(1,1) == "!" then
			execline = msg:sub(2)
			if pcall (evalstr) then
				if execline and #execline>0 then
					c:privmsg (user, execline) -- eval
				else
					c:privmsg (user, "Uhm?") -- eval
				end
			else
				if type (execline) == "string" then
					c:privmsg (user, "error: "..execline)
				else
					c:privmsg (user, "error: oops ".. type (execline))
				end
			end
		else
			c:privmsg (user, msg) -- echo
		end
	end)
c:on ("quit", function (x)
		c:close ()
		process.exit (0)
	end)
c:on ("connected", function ()
		p ("GOGOGOGO")
	end)
c:on ("ping", function (x)
		p ("---> PING ",x)
	end)
c:on ("users", function (x, u)
		p ("---> USERS FOR CHANNEL "..x.." <----")
		p (u)
	end)
c:on ("servermsg", function (host, msg)
	p ("SERVERMSG", msg)
	end)

function irc_cmd (line)
	if line == "/quit" then
		c:quit ()
	elseif line:sub (1, 6) == "/join " then
		channel = line:sub (6)
		c:join (channel)
	elseif line:sub (1, 6) == "/part " then
		channel = line:sub (7)
		c:part (channel)
	elseif line:sub (1, 5) == "/part" then
		c:part (channel)
	elseif line:sub (1, 7) == "/query " then
		channel = line:sub (7)
	elseif line:sub (1, 7) == "/names" then
		c:names (channel)
	elseif line:sub (1, 1) == "!" then
		c:write (line:sub (2).."\n")
	else
		c:privmsg (channel, line)
	end
end

c:connect (host, port, nick)
process.stdin:read_start ()
process.stdin:on ("data", function (line)
	irc_cmd (line:sub (1, #line-1))
end)
