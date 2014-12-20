-- author -- pancake@nopcode.org --
-- TODO: use emitter api
-- TODO: check SSL certificate

local Emitter = require('core').Emitter
local dns = require('dns')
local TCP = require('uv').Tcp
local table = require('table')
local TLS = require('tls', false)
local string = require('string')
local base64 = require('./base64.lua')

-- copypasta
-- Compatibility: Lua-5.0
function split(str, delim, maxNb)
  -- Eliminate bad cases...
  if string.find(str, delim) == nil then
    return { str }
  end
  if maxNb == nil or maxNb < 1 then
    maxNb = 0    -- No limit
  end
  local result = {}
  local pat = "(.-)" .. delim .. "()"
  local nb = 0
  local lastPos
  for part, pos in string.gmatch(str, pat) do
    nb = nb + 1
    result[nb] = part
    lastPos = pos
    if nb == maxNb then break end
  end
  -- Handle the last field
  if nb ~= maxNb then
    result[nb + 1] = string.sub(str, lastPos)
  end
  return result
end


local IRC = Emitter:extend()

function IRC:initialize()
  self.sock = nil
  self.buffer = ""
end

function IRC:write(msg)
  self.sock:write(msg)
  self:emit("dataout", msg)
end

function IRC:action(chan, msg)
  self:ctcp("ACTION", chan, msg)
end

function IRC:ctcp(ctcp, chan, msg)
  self:write("PRIVMSG "..chan.." :\x01"..ctcp.." "..msg.."\n")
end

function IRC:privmsg(chan, msg)
  if msg:sub(1,4) == "/me " then
    self:action(chan, msg:sub (5))
  else
    self:write("PRIVMSG "..chan.." :"..msg.."\n")
  end
end

function IRC:join(chan)
  self:write("JOIN "..chan.."\n")
  self.chan = chan
end

function IRC:part(chan)
  self:write("PART "..chan.."\n")
end

function IRC:quit()
  self:write("QUIT\n", function ()
    self:emit("quit")
  end)
end

function IRC:close()
  if self.sock.socket then
    self.sock.socket:close() -- SSL
  else
    self.sock:close() -- TCP
  end
end

function IRC:names(chan)
  self:write("NAMES "..chan.."\n")
end

function IRC:_fin_connect(user, nick, host, options)
  local later = false
  if options and options.sasl_auth then
    options.sasl_user = user
    self:write("CAP REQ :sasl\n")
    later = true
  end

  self:write("NICK "..nick.."\n")
  self:write("USER "..user.." 0 "..host.." :"..nick.."\n")
  if not later then
    self:emit("connected")
  end
end

function IRC:connect(host, port, user, nick, options)
  dns.resolve4(host, function (err, addresses)
    host = addresses[1]
    if options['ssl'] then
      if not TLS then
        error ("luvit cannot require ('tls')")
      end
      TLS.connect (port, host, {}, function (err, client)
        self.sock = client
        self:_handle(client, options)
        self:_fin_connect(user, nick, host, options)
      end)
    else
      local sock = TCP:new ()
      self.sock = sock
      sock:connect(host, port)
      self:_handle(sock, options)
      sock:on("connect", function ()
        sock:readStart()
        self:_fin_connect(user, nick, host, options)
      end)
    end
  end)
end

function IRC:_handle(sock, options)
  sock:on("data", function (line)
    local lines = split(self.buffer..line, "\r\n")
    if line:len() < 2 or line:sub(line:len()-1,line:len()) ~= "\r\n" then
      self.buffer = lines[#lines]
      table.remove(lines)
    else
      self.buffer = ""
    end
    if not #lines then
      return
    end

    local x
    for i = 1, #lines do
      x = lines[i]
      local w = split (x, " ")
      if w[1] == "PING" then
        local s = x:sub(5)
        self:emit("ping", s)
        sock:write("PONG "..s.." :"..s.."\n")
      elseif w[1] == "ERROR" then -- server message
        p("WTF I CAN HAZ AN ERROR")
        local msg = w[2]
        self:emit("servererror", msg)
      elseif w[2] == "372" then -- server message
        local msg = "" for i=4,#w do msg = msg..w[i].." " end
        msg = msg:sub (2)
        self:emit("servermsg", w[1], msg)
      elseif w[2] == "353" then -- list of users
        local chan = w[5]
        local msg = "" for i=7,#w do
          p(i, w[i])
          msg = msg..w[i].." "
        end
        self:emit("users", chan, split (msg, " "))
      elseif w[2] == "903" then -- sasl auth success
        self:write("CAP END\n")
      elseif w[2] == "MODE" then
        self:emit("connected")
      elseif w[2] == "NOTICE" then
        local msg = "" for i=4,#w do msg = msg..w[i].." " end
        msg = msg:sub(2)
        self:emit("notice", w[1], msg)
      elseif w[2] == "JOIN" then
        local chan = w[3]
        self:emit("join", chan)
      elseif w[2] == "CAP" then
        if w[4] == "ACK" then
          local caps = "" for i=5,#w do caps = caps..w[i].." " end
          if caps:sub(2):find('sasl') then
            self:write("AUTHENTICATE PLAIN\n")
          end
        end
      elseif w[1] == "AUTHENTICATE" then
        if w[2] == "+" then
          local a = options.sasl_user.."\0"..options.sasl_user.."\0"..options.sasl_auth
          self:write("AUTHENTICATE "..base64.enc(a).."\n")
        end
      elseif w[2] == "PRIVMSG" then
        local msg = "" for i=4,#w do msg = msg..w[i].." " end
        msg = msg:sub(2)
        if msg:sub (1, 8) == "\x01ACTION" then
          msg =
          self:emit("action", w[3], msg)
        else
          local nick = w[1]
          if w[3]:sub(1,1) == '#' then
            nick = w[3]
          else
            nick = nick:sub(2, nick:find ("!")-1)
          end
          self:emit("privmsg", w[3], w[1]:sub (2, w[1]:find ("!")-1), msg)
        end
      end

      self:emit("data", x)
    end
  end)
  sock:on("error", function (x)
    self:emit("error", x)
  end)
end


return IRC
