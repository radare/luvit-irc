-- author -- pancake@nopcode.org --
-- TODO: use emitter api
-- TODO: check SSL certificate

local dns = require ('dns')
local TCP = require ('uv').Tcp
local table = require ('table')
local TLS = require ('tls', false)
local IRC = {}

-- copypasta
function split(str, pat)
	local t = {}  -- NOTE: use {n = 0} in Lua-5.0
	local fpat = "(.-)" .. pat
	local last_end = 1
	local s, e, cap = str:find (fpat, 1)
	while s do
		if s ~= 1 or cap ~= "" then
	 table.insert(t,cap)
		end
		last_end = e+1
		s, e, cap = str:find(fpat, last_end)
	end
	if last_end <= #str then
		cap = str:sub(last_end)
		table.insert(t, cap)
	end
	return t
end

function IRC.new ()
	local client = {}
	client.handlers = {}
	client.sock = nil
	client.emit = function (self, ev, a0, a1)
		if self.handlers[ev] then
			self.handlers[ev](a0, a1)
		end
	end
	client.on = function (self, ev, fn)
		self.handlers[ev] = fn
	end
	client.write = function (self, msg)
		self.sock:write (msg)
	end
	client.action = function (self, chan, msg)
		self:ctcp ("ACTION", chan, msg)
	end
	client.ctcp = function (self, ctcp, chan, msg)
		self.sock:write ("PRIVMSG "..chan.." :\x01"..ctcp.." "..msg.."\n")
	end
	client.privmsg = function (self, chan, msg)
		if msg:sub(1,4) == "/me " then
			self:action (chan, msg:sub (5))
		else
			self.sock:write ("PRIVMSG "..chan.." :"..msg.."\n")
		end
	end
	client.join = function (self, chan)
		self.sock:write ("JOIN "..chan.."\n")
		self.chan = chan
	end
	client.part = function (self, chan)
		self.sock:write ("PART "..chan.."\n")
	end
	client.quit = function (self)
		self.sock:write ("QUIT\n", function ()
			client:emit ("quit")
		end)
	end
	client.close = function (self)
		if self.sock.socket then
			self.sock.socket:close () -- SSL
		else
			self.sock:close () -- TCP
		end
	end
	client.names = function (self, chan)
		self.sock:write ("NAMES "..chan.."\n")
	end
	client.connect = function (self, host, port, nick, options, fun)
		dns.resolve4(host, function (err, addresses)
			host = addresses[1]
			if options['ssl'] then
				if not TLS then
					error ("luvit cannot require ('tls')")
				end
				TLS.connect (port, host, {}, function (err, client)
					self.sock = client
					self:connect2 (client)
					client:write ("NICK "..nick.."\n")
					client:write ("USER "..nick.." "..nick.." "..host.." :"..nick.."\n")
				end)
			else
				local sock = TCP:new ()
				self.sock = sock
				sock:connect (host, port)
				self:connect2 (sock)
				sock:on ("connect", function ()
					sock:readStart ()
					p ('sock:on(complete)')
					-- auth sock
					sock:write ("NICK "..nick.."\n")
					sock:write ("USER "..nick.." "..nick.." "..host.." :"..nick.."\n")
					self:emit ("connected", x)
				end)
			end
		end)
	end
	client.connect2 = function (self,sock)
		sock:on ("data", function (line)
			-- hack for newlines
			local lines = split (line, "\r\n")
			if not lines then lines = {line} end
			for i = 1, #lines do
				x = lines[i]
				-- if nl then x = x:sub (0, nl-1) end
				local w = split (x, " ")
				--p(w)
				-- p (w[1], w[2], w[3])
				if w[1] == "PING" then
					local s = x:sub(5)
					self:emit ("ping", s)
					sock:write ("PONG "..s.." :"..s.."\n")
				elseif w[1] == "ERROR" then -- server message
					p ("WTF I CAN HAZ AN ERROR")
				elseif w[2] == "372" then -- server message
					local msg = "" for i=4,#w do msg = msg..w[i].." " end
					msg = msg:sub (2)
					self:emit ("servermsg", w[1], msg)
				elseif w[2] == "353" then -- list of users
					local chan = w[5]
					local msg = "" for i=7,#w do 
						p(i, w[i])
						msg = msg..w[i].." " 
					end
					self:emit ("users", chan, split (msg, " "))
				elseif w[2] == "NOTICE" then
					local msg = "" for i=4,#w do msg = msg..w[i].." " end
					msg = msg:sub (2)
					self:emit ("notice", w[1], msg)
				elseif w[2] == "JOIN" then
					local chan = w[3]
					self:emit ("join", chan)
				elseif w[2] == "PRIVMSG" then
					local msg = "" for i=4,#w do msg = msg..w[i].." " end
					msg = msg:sub (2)
					if msg:sub (1, 8) == "\x01ACTION" then
						msg = 
						self:emit ("action", w[3], msg)
					else
						local nick = w[1]
						if w[3]:sub (1,1) == '#' then
							nick = w[3]
						else
							nick = nick:sub (2, nick:find ("!")-1)
						end
						self:emit ("privmsg", nick, msg)
					end
				end
			end
			self:emit ("data", x)
--
		end)
		sock:on ("error", function (x)
			self:emit ("error", x)
		end)
	end
	return client
end

return IRC
