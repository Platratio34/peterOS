local log = pos.Logger('/home/.pgmLog/net.log', false, true)

---POS networking module
_G.net = {}
require("encrypt")
shell.run('/os/net/NetInterface.lua')

-- The modem used by the module
-- local modem = nil
local defaultInterface = nil ---@type NetInterface

-- +------------------+
-- | Hardware Address |
-- +------------------+

---Gets the computer's hardware address (hex string)
---@return string hwAddress hardware address as hex string
net.getHWAddr = function()
    return defaultInterface:getHWAddress()
end

-- +---------------------+
-- | Network config data |
-- +---------------------+

-- Configuration file path
local cfgPath = "/home/.appdata/net.cfg"
-- Network configuration object
local cfg = {
    hostname = "",
    respondToPing = true,
    originHostname = nil,
}
local config = pos.Config(cfgPath, cfg, true)
cfg = config.data

-- +----------------+
-- | IP Information |
-- +----------------+

-- IP address type
local ipv = "IPV4"
---Gets the type of address the computer uses (currently IPV4)
---@return string version gets the IP version used by the module
net.getIPV = function()
    return ipv
end

--- Default message wait time out in seconds
net.DEFAULT_TIMEOUT = 5
net.NET_MESSAGE_EVENT = "net_message" ---On net message event

---Format a numeric IPV4 in the the standard format
---@param ip NetAddress IP address either as number, or hardware address
---@return string ip IP address formatted in IPV4 x:x:x:x
net.ipFormat = function(ip)
    expect(1, ip, "number", "string")
    if type(ip) == "string" then return ip end

    if ip < 0 or ip > 0xffffffff then
        return tostring(ip)
    end

    local str = ""
    for i = 1, 4 do
        if i > 1 then str = "." .. str end
        str = (ip % 0x100) .. str
        ip = math.floor(ip / 0x100)
    end
    return str
end

---Turns an IP string into a numerical IP address
---@param ip string|NetAddress IP Address as x:x:x:x
---@return NetAddress ip Address as number
net.ipToNumber = function(ip)
    if type(ip) == 'number' then return ip end
    local num = 0
    local good = false
    for octet in string.gmatch(ip, "(%d+)") do
        num = num * 256 + tonumber(octet)
        good = true
    end
    if not good then
        return -1
    end
    return num
end

---Check if a given address is an IPV4 string
---@param ip any
---@return boolean isIPV4
function net.isIPV4(ip)
    if type(ip) ~= 'string' then
        return false
    end
    local v1 = ip:find('^%d%d?%d?.%d%d?%d?.%d%d?%d?.%d%d?%d?$')
    return v1 ~= nil
end

---Gets the current IP of the computer (numeric)
---@return NetAddress ip The numeric IP of the computer
net.getIP = function()
    return defaultInterface:getIp() or -1
end
---Get the address mask of the local network (numeric)
---@return number? mask Numeric IP subnet mask (ie 0xff00 for 255:255:0:0)
net.getIPMask = function()
    return defaultInterface:getSubnetMask()
end

-- +-------------------------+
-- | Internal Base Functions |
-- +-------------------------+

-- messages waiting processing
-- local messages = {}

local msgHandlers = {} ---@type fun(msg: NetMessage)[]
local msgHandlerCID = 1;
---Run event handlers for valid message
---@param msg NetMessage
local function onMsg(msg)
    for id, handler in pairs(msgHandlers) do
        -- print('running msg handler '..id)
        local suc, error = pcall(handler, msg)
        -- handler(msg)
        if not suc then
            log:warn('NET Handler Error: ' .. error)
            printError('NET Handler Error: ' .. error)
        end
    end
end

-- Current message ID
-- local msgId = os.epoch('utc')
---Get the current message ID
---@return number id id for last message
net.getMsgId = function()
    return defaultInterface:getMsgId()
end
---Increment and return the current message ID
---@return number id id for next message
net.useMsgId = function()
    return defaultInterface:useMsgId()
end

---Gets the IP address associated with a given hostname
---@param hostname string|NetAddress Hostname, IP address, or HW address
---@return NetAddress ip Numeric IP address or HW address
net.realizeHostname = function(hostname)
    return defaultInterface:resolveHostname(hostname)
end

-- +------------------------+
-- | Modem Helper Functions |
-- +------------------------+

---Get a modem on side, and add network functions
---@param side string Side of computer: <code>front</code>, <code>back</code>, <code>left</code>, <code>right</code>, <code>top</code>, <code>bottom</code>
---@return ModemPeripheral|nil modem Modem handle
---@deprecated
net.getModem = function(side)
    error('Deprecated function, use NetInterfaces instead', 2)
end

-- +--------------------+
-- | Hostname functions |
-- +--------------------+

---Returns the network hostname of the computer
---@return string? hostname Current hostname (defaults to "")
net.getHostname = function()
    return defaultInterface:getHostname()
end

---Sets the network hostname of the computer. Requires sudo.
---Returns if setting the hostname succeeded
---@param new string New hostname
---@return boolean suc If the hostname was set successfully
---@deprecated
net.setHostname = function(new)
    error('Deprecated function?', 2)
    -- expect(1, new, "string")

    -- cfg.hostname = new
    -- -- local f = fs.open(cfgPath, "w")
    -- -- if f == nil then
    -- --     log:error("Unable to change hostname")
    -- --     error("Unable to change hostname", 0)
    -- --     return false
    -- -- end
    -- -- f.write(textutils.serialiseJSON(cfg))
    -- -- f.close()
    -- config:save()
    -- sendMsg(10000, 0xC0A80000, { type = "net.ip.changeHost" }, { hostname = new })
    -- return true
end

-- +----------------+
-- | Setup function |
-- +----------------+

-- If the network module has been setup
-- local isSetup = false

---If the network module has been setup
---@return boolean setup if module is setup
net.isSetup = function()
    return defaultInterface and defaultInterface:getIp() ~= nil
end
---Gets the currently used modem
---@return ModemPeripheral|nil modem Current primary modem
---@deprecated
net.getCModem = function()
    return defaultInterface:getModem()
end
---Get the current default Network Interface
---@return NetInterface interface
function net.getInterface()
    return defaultInterface
end

local msgHandlerId = -1
---Setup the network module, returns false on a failure
---@param mdm? ModemPeripheral Primary modem (optional)
---@param ip? number Numeric IP address (optional)
---@return boolean setup If the module is not setup
net.setup = function(mdm, ip)
    expect(1, mdm, "table", "nil")
    expect(1, ip, "number", "nil")

    if defaultInterface and defaultInterface:getIp() then
        return true
    end

    if defaultInterface then
        return defaultInterface:setup()
    else
        defaultInterface = net.NetInterface(nil, mdm, ip)
        defaultInterface:setConfig('/home/.appdata/net.cfg')
        msgHandlerId = defaultInterface:addMsgHandler(onMsg)
    end
    return defaultInterface:setup()

    -- if isSetup then return true end
    -- if not fs.exists(hwAddrPath) then
    --     hwAddr = string.randomString(16, { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f' })
    --     local f = fs.open(hwAddrPath, "w")
    --     if f == nil then
    --         log:error("Failed to write Hardware Address, Network module unavailable")
    --         error("Failed to write Hardware Address, Network module unavailable", 0)
    --         return false
    --     end
    --     f.write(hwAddr)
    --     f.close()
    -- else
    --     local f = fs.open(hwAddrPath, "r")
    --     if f == nil then
    --         log:error("Failed to read Hardware Address, Network module unavailable")
    --         error("Failed to read Hardware Address, Network module unavailable", 0)
    --         return false
    --     end
    --     hwAddr = f.readAll()
    --     f.close()
    -- end

    -- if mdm == nil then
    --     local modems = { peripheral.find("modem", function(name, test)
    --         return test.isWireless()
    --     end) }
    --     if #modems == 0 then
    --         modems = { peripheral.find("modem"), }
    --         if #modems == 0 then
    --             log:error("No Modem Attached")
    --             error("No Modem Attached", 0)
    --             return false
    --         end
    --     end
    --     modem = modems[1]
    -- else
    --     modem = mdm
    -- end

    -- if ip == nil then
    --     local ipGetBody = {}
    --     if cfg.hostname ~= "" then
    --         ipGetBody.hostname = cfg.hostname
    --     end
    --     for i = 1, 3 do
    --         -- print("Getting IP")
    --         sendMsg(10000, -1, { type = "net.ip.req" }, ipGetBody)
    --         if waitForMsg(function(port, msg)
    --                 if port ~= 10000 then return true end
    --                 if msg.dest == "hw:" .. hwAddr and msg.header.type == "net.ip.acp.return" then
    --                     return false
    --                 end
    --                 return true
    --             end, 10) == "timeout" then
    --             log:error("Failed to get IP address, Trying again in 30 seconds")
    --             -- return false
    --         else
    --             log:info('Got IP address: ' .. net.ipFormat(ipAddr))
    --             break
    --         end
    --         os.sleep(30)
    --     end
    --     if type(ipAddr) ~= "number" or ipAddr < 0 then
    --         print(ipAddr)
    --         ipAddr = -1
    --         log:error("Failed to get IP address, Network module unavailable")
    --         error("Failed to get IP address, Network module unavailable", 0)
    --         return false
    --     end
    -- else
    --     ipAddr = ip
    -- end

    -- for _, port in pairs(net.standardPorts) do
    --     net.open(port)
    -- end

    -- isSetup = true
    -- return true
end

-- +----------------+
-- | Send functions |
-- +----------------+

---Send a message with a type header.
---@param port number Network port for message (see net.standardPorts)
---@param dest number|string Destination IP address, HW address, or hostname
---@param msgType string Message type
---@param body any Message body
---@return number id Message ID or -1 on error
net.send = function(port, dest, msgType, body)
    return defaultInterface:send(port, dest, msgType, body)
    -- expect(1, port, "number")
    -- expect(2, dest, "number", "string")
    -- expect(3, msgType, "string")

    -- if not net.setup() then
    --     return -1
    -- end
    -- local head = {
    --     type = msgType
    -- }
    -- return sendMsg(port, dest, head, body)
end
---Send a message with a type header, and waits for the reply.
---Returns the message, "setup_fail", "sent_fail", or "timeout" after 2 seconds
---@param port number Network port for message (see net.standardPorts)
---@param dest NetAddress|string Destination IP address, HW address, or hostname
---@param msgType string Message type
---@param body any Message body
---@param timeout? number Reply timeout in seconds (default is 2 seconds, set to -1 to disable)
---@return NetMessage|string rsp Response message, or error string
net.sendSync = function(port, dest, msgType, body, timeout)
    return defaultInterface:sendSync(port, dest, msgType, body, timeout)
    -- expect(1, port, "number")
    -- expect(2, dest, "number", "string")
    -- expect(3, msgType, "string")
    -- expect(5, timeout, "nil", "number")

    -- if not net.setup() then
    --     return "setup_fail"
    -- end
    -- net.open(port)
    -- local head = {
    --     type = msgType
    -- }
    -- local id = sendMsg(port, dest, head, body)
    -- if id == -1 then
    --     return "send_fail"
    -- end
    -- log:debug(("Waiting for reply w/ id `%d`"):format(id))
    -- return waitForMsg(function(rPort, message)
    --     if rPort ~= port then
    --         log:debug(('p `%d` != `%d`'):format(rPort, port))
    --         return true
    --     end
    --     if message.dest == ipAddr then
    --         if message.msgid == id then
    --             log:debug('- Found message')
    --             return false
    --         else
    --             log:debug(('i `%d` != `%d`'):format(message.msgid, id))
    --         end
    --     else
    --         log:debug(('d `%s` != `%s`'):format(message.dest, ipAddr))
    --     end
    --     return true
    -- end, timeout)
end

---Send a message with a custom header. Header should include a 'type' parameter.
---@param port number Network port for message (see net.standardPorts)
---@param dest NetAddress|string Destination IP address, HW address, or hostname
---@param head NetMessage.Header Message header, should include type parameter
---@param body any Message body
---@return number id Message ID or -1 on error
net.sendAdv = function(port, dest, head, body)
    return defaultInterface:sendAdv(port, dest, head, body)
    -- expect(1, port, "number")
    -- expect(2, dest, "number", "string")
    -- expect(3, head, "table")

    -- if not net.setup() then
    --     return -1
    -- end
    -- net.open(port)
    -- return sendMsg(port, dest, head, body)
end
---Send a message with a custom header, and waits for the reply. Header should include a 'type' parameter.
---Returns the message, "setup_fail", "send_fail", or "timeout" after 2 seconds
---@param port number Network port for message (see net.standardPorts)
---@param dest NetAddress|string Destination IP address, HW address, or hostname
---@param head NetMessage.Header Message header, should include type parameter
---@param body any Message body
---@param timeout? number Reply timeout in seconds (default is 2 seconds, set to -1 to disable)
---@return NetMessage|string rsp Response message, or error string
net.sendAdvSync = function(port, dest, head, body, timeout)
    return defaultInterface:sendAdvSync(port, dest, head, body, timeout)
    -- expect(1, port, "number")
    -- expect(2, dest, "number", "string")
    -- expect(3, head, "table")
    -- expect(5, timeout, "nil", "number")

    -- if not net.setup() then
    --     return "setup_fail"
    -- end
    -- net.open(port)
    -- local id = sendMsg(port, dest, head, body)
    -- if id == -1 then
    --     return "send_fail"
    -- end
    -- log:debug(("Waiting for reply w/ id `%d`"):format(id))
    -- return waitForMsg(function(rPort, message)
    --     if rPort ~= port then
    --         log:debug(('p `%d` != `%d`'):format(rPort, port))
    --         return true
    --     end
    --     -- if message.header == head and message.body == body then return true end
    --     if message.dest == ipAddr then
    --         if message.msgid == id then
    --             log:debug('- Found message')
    --             return false
    --         else
    --             log:debug(('i `%d` != `%d`'):format(message.msgid, id))
    --         end
    --     else
    --         log:debug(('d `%s` != `%s`'):format(message.dest, ipAddr))
    --     end
    --     return true
    -- end, timeout)
end

---Reply to a message
---@param port number Network port for reply (see net.standardPorts)
---@param old NetMessage Message object to reply to
---@param head NetMessage.Header Reply header, should include type parameter
---@param body any Reply body
---@return number id Reply id
net.reply = function(port, old, head, body)
    return defaultInterface:reply(port, old, head, body)
    -- expect(1, port, "number")
    -- expect(2, old, "table")
    -- expect(3, head, "table")

    -- if not net.setup() then
    --     return -1
    -- end
    -- net.open(port)
    -- if old.header.conId then head.destConId = old.header.conId end
    -- if old.header.domain then head.originDomain = old.header.domain end
    -- head.publicKey = nil
    -- return sendMsg(port, old.origin, head, body, old.msgid)
end

-- +----------------+
-- | Wait functions |
-- +----------------+

---Waits for a message on a particular port, with a timeout.
---@param port number Network port to listen on (`-1` for any)
---@param time? number *(Optional)* Timeout in seconds (default is `net.DEFAULT_TIMEOUT` seconds, set to `-1` to disable)
---@return string|NetMessage rsp Message or error string
net.waitForMsg = function(port, time)
    return defaultInterface:waitForMessage(port, function(_, msg) return msg.dest ~= defaultInterface:getIp() end, time)
end

---Waits for a message on a particular port, with a timeout.
---Check function should return true on the message you want, and takes the message as a parameter.
---@param port number Network port to listen on (`-1` for any)
---@param time number Timeout in seconds (set to `-1` to disable)
---@param check fun(msg: NetMessage): boolean Message check function, takes message as parameter, and returns continue waiting
---@return string|NetMessage rsp Message or error string
net.waitForMsgAdv = function(port, time, check)
    return defaultInterface:waitForMessage(port, function(_,msg) return check(msg) end, time)
end

---Wait for a message matching check function
---@param check nil|fun(port: number, msg: NetMessage): boolean Check function, returns `false` on message you want
---@param time number? Timeout (`-1` to disable, defaults to `net.DEFAULT_TIMEOUT`)
---@return NetMessage|string msg
net.waitForMsgAll = function(check, time)
    return defaultInterface:waitForMessage(nil, check, time)
end

---Checks is a modem message is a valid network message
---@param port number Network port of message
---@param message table Message to validate
---@return boolean valid Message is valid
net.validMsg = function(port, message)
    return defaultInterface:validMsg(port, message)
end

---Register a message handler
---@param func fun(msg: NetMessage) Handler function, takes a message object
---@return number id Handler Id, used to unregister handlers
net.registerMsgHandler = function(func)
    msgHandlers[msgHandlerCID .. ""] = func
    local id = msgHandlerCID
    msgHandlerCID = msgHandlerCID + 1
    return id
end
---Unregister a message handler
---@param id number Handler Id
net.unregisterMsgHandler = function(id)
    msgHandlers[id .. ""] = nil
end
---Get the id of the next message handler
---@return number id next handler id
net.getCIDofNetHandlers = function()
    return msgHandlerCID
end

---Subscribe to a multicast group. IP must be between `224.0.0.0` (`0xe0000000`) and `239.255.255.255` (`0xefffffff`).
---@param ip number Multicast group IP
---@param handler fun(ip: number, msg: NetMessage) Multicast message handler
---@return integer id Handler Id, used to unregister subscriber
function net.multicastSubscribe(ip, handler)
    return defaultInterface:multicastSubscribe(ip, handler)
end
---Remove a multicast subscription, uses ID from subscription
---@param ip number Multicast group IP
---@param id integer Handler Id, from `net.multicastSubscribe(ip, handler)`
function net.multicastUnsubscribe(ip, id)
    defaultInterface:multicastUnsubscribe(ip, id)
end

-- +-------------------+
-- | Utility Functions |
-- +-------------------+

---Returns a string version of the message for debug and logging.
---Includes: origin, destination, port, id, connection Id, type, and serialized body
---@param msg NetMessage Message to string
---@return string message String version of message
net.stringMessage = function(msg)
    expect(1, msg, "table")

    local str = ""
    if type(msg.origin) == "number" then
        str = net.ipFormat(msg.origin)
    else
        str = tostring(msg.origin)
    end
    str = str .. " -> "
    if type(msg.dest) == "number" then
        str = str .. net.ipFormat(msg.dest)
    else
        str = str .. tostring(msg.dest)
    end
    str = str .. ":" .. msg.port
    str = str .. " | #" .. msg.msgid
    if msg.header.conId then
        str = str .. ":" .. msg.header.conId
    end
    if #msg.header == 1 then
        str = str .. " | " .. msg.header.type .. " : "
    else
        str = str .. " | " .. textutils.serialiseJSON(msg.header) .. " : "
    end
    if msg.body.cipher then
        str = str .. 'cipher = ' ..  textutils.serialiseJSON(msg.body.cipher)
        str = str .. ',\nsig = ' ..  textutils.serialiseJSON(msg.body.sig)
    else
        str = str .. textutils.serialise(msg.body)
    end
    return str
end

---Open the modem on port (10,000 through 20,000)
---@param port number Network port to open (see net.standardPorts)
net.open = function(port)
    expect(1, port, "number")
    defaultInterface:open(port)
    -- if modem then modem.open(port) end14
end

---Standard Networking ports
net.standardPorts = {
    ---Network control messages
    network = 10000,
    ---Redstone Text Transfer Protocol (in-game HTTP) messages
    rttp = 10080,
    ---Redstone Text Transfer Protocol Secure (in-game HTTPS) messages
    rttps = 10081,
    ---File Transfer Protocol messages
    ftp = 10021,
    ---RMail messages
    rmail = 10025,
    ---Remote user system
    remoteUser = 10234,
}

---Ping destination and print time
---@param dest NetAddress|string Destination hostname, IP address, HW address
net.ping = function(dest)
    local time, err = defaultInterface:ping(dest)
    if time > -1 then
        error('Error pinging ' .. net.ipFormat(net.realizeHostname(dest)) .. ': ' .. err, 2)
    end
    print("Received return from " .. net.ipFormat(net.realizeHostname(dest)) .. " after " .. (time/1000) .. "s")
    -- local time = os.time()
    -- local rt = net.sendSync(net.standardPorts.network, dest, "ping", {})
    -- if type(rt) ~= "table" then
    --     log:error('Error pinging ' .. net.ipFormat(net.realizeHostname(dest)) .. ': ' .. rt)
    --     error('Error pinging ' .. net.ipFormat(net.realizeHostname(dest)) .. ': ' .. rt, 0)
    --     return
    -- end
    -- local elapsed = os.time() - time
    -- log:debug("Received return from " .. net.ipFormat(net.realizeHostname(dest)) .. " after " .. elapsed .. "s")
    -- print("Received return from " .. net.ipFormat(net.realizeHostname(dest)) .. " after " .. elapsed .. "s")
end

---Split a url string
---@param url string URL string: protocol://domain/path
---@return string|nil protocol Protocol string (if provided)
---@return string domain Domain, including sub domains
---@return string path Path with no leading /
net.splitUrl = function(url)
    local protocol = nil
    if string.cont(url, '://') then
        local s, e = string.find(url, '://')
        protocol = string.sub(url, 1, s - 1)
        url = string.sub(url, e + 1)
    end
    local domain = url
    local path = ''
    local parts = string.split(domain, '/')
    domain = parts[1]
    if #parts >= 2 then
        path = table.concat(parts, '/', 2)
    end
    return protocol, domain, path
end

---Get an origin string for given message
---@param msg NetMessage
---@return string origin
function net.getOriginString(msg)
    local origin = msg.origin .. ''
    if msg.header.originDomain then
        origin = msg.header.originDomain --[[@as string]]
    elseif msg.header.conId then
        origin = origin .. ':' .. msg.header.conId
    end
    return origin
end

---Sets if the net module should log all messages
---@param vb boolean If all messages should be logged
---@deprecated
net.setLogVerbose = function(vb) end

shell.setAlias('net', '/os/net/cmd.lua')
shell.run("/os/net/socket.lua")
loadfile('/os/net/cert.lua')(require, log)

---@alias NetAddress number|string IP or HW address

---@class NetMessage Networking message struct
---@field origin NetAddress Origin IP or HW of the message
---@field dest NetAddress Destination IP or HW of message
---@field port number Networking port for message
---@field header NetMessage.Header Header table
---@field body nil|table|string Message body
---@field msgid number Message ID
---@field reply fun(self, port: number, head: NetMessage.Header, body: nil|table|string) Reply to this message

---@class NetMessage.Header Networking message header table
---@field type string Net message type
---@field encrypted boolean|nil If the message body is encrypted
---@field publicKey byteArray|nil Body encryption public key
---@field domain string|nil Destination domain name
---@field conId number|nil NAT connection ID
---@field destConId number|nil Destination NAT connection ID
---@field originDomain string|nil (REPLY ONLY) Domain the request was sent to
---@field certificate net.Certificate? Certificate