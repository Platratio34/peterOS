local expect = require "cc.expect"
local log = pos.Logger('/home/.pgmLog/net.log', false, true)
local logVerboseMessages = false
local function logVerboseMessage(text)
    if not logVerboseMessages then return end
    log:debug(text)
end

local remoteKeys = {}

---POS networking module
_G.net = {}
require("encrypt")

-- The modem used by the module
local modem = nil

-- +------------------+
-- | Hardware Address |
-- +------------------+

--- The path to the hardware address file
local hwAddrPath = "/hw.addr"
-- The hardware address of the computer, unique to the device regardless of network
local hwAddr = ""
---Gets the computer's hardware address (hex string)
---@return string hwAddress hardware address as hex string
net.getHWAddr = function()
    return hwAddr
end

-- +---------------------+
-- | Network config data |
-- +---------------------+

-- Configuration file path
local cfgPath = "/home/.appdata/net.cfg"
-- Network configuration object
local cfg = {
    hostname = ""
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

-- IP address of the computer, expressed as a number
---@type number
local ipAddr = 0x00000000
-- The address local mask of the network
---@type number
local ipMask = 0x0000ffff
-- The IP address of the DHCP and DNS server
---@type number
local dhcpIP = 0xC0A80000

local addrTbl = {}
local dnsCache = {}

-- IP lease expire time
local leaseTime = 9e99

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

---Gets the current IP of the computer (numeric)
---@return NetAddress ip The numeric IP of the computer
net.getIP = function()
    return ipAddr
end
---Get the address mask of the local network (numeric)
---@return number mask Numeric IP subnet mask (ie 0xff00 for 255:255:0:0)
net.getIPMask = function()
    return ipMask
end

-- +-------------------------+
-- | Internal Base Functions |
-- +-------------------------+

-- messages waiting processing
local messages = {}

local msgHandlers = {}
local msgHandlerCID = 1;
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
local msgId = os.epoch('utc')
---Get the current message ID
---@return number id id for last message
net.getMsgId = function()
    return msgId
end
---Increment and return the current message ID
---@return number id id for next message
net.useMsgId = function()
    msgId = msgId + 1
    return msgId
end

local function encryptMsg(dest, head, body)
    local destIPC = dest
    if head.conId then
        destIPC = destIPC .. head.conId
    end
    if head.domain then
        destIPC = head.domain
    end

    if head.publicKey then
        log:debug('Message already had public key')
        return body
    end
    head.publicKey = net.encrypt.getPublicKey()
    if remoteKeys[destIPC] and body then
        local cipher, sig = net.encrypt.encrypt(body, remoteKeys[destIPC])
        body = {
            cipher = cipher,
            sig = sig,
        }
        head.encrypted = true
        -- log:debug('enc body: ' .. textutils.serialiseJSON(body))
        logVerboseMessage('Encrypted message for '..destIPC..' with body type '..type(body))
    end
    return body
end

---Send a message over the given port, with destination, header, and body.
-- Returns the message ID or -1 for failure
---@param port number Network port for message (see net.standardPorts)
---@param dest NetAddress|string Destination name or IP address
---@param head NetMessage.Header Message header, must have type parameter
---@param body any Message body
---@param id number|nil Outgoing message ID (optional)
---@return number id message ID or -1 on failure
local function sendMsg(port, dest, head, body, id)
    expect(1, port, "number")
    expect(2, dest, "number", "string")
    expect(3, head, "table")
    expect(5, id, "number", "nil")

    if modem == nil then return -1 end

    if leaseTime > -1 and leaseTime < os.epoch() + (8.64e7 * 3) then
        -- print("trying to renew ip lease")
        local msg = { ---@type NetMessage
            origin = ipAddr,
            dest = dhcpIP,
            port = 10000,
            header = { type = "net.ip.renew", publicKey = net.encrypt.getPublicKey() },
            body = { hwaddr = hwAddr },
            msgid = net.useMsgId(),
            reply = function() end
        }
        modem.transmit(10000, 10000, msg)
        if net.waitForMsgAll(function(rPort, rMsg)
                if rPort == 100000 then
                    if rMsg.origin == dhcpIP and rMsg.header.type == "net.ip.renew.return" then
                        if rMsg.body.action == "renewed" then
                            ipAddr = rMsg.body.ip
                            ipMask = rMsg.body.mask
                            leaseTime = rMsg.body.time
                            addrTbl = rMsg.body.addrTbl
                            return false
                        end
                    end
                end
                return true
            end, 2) == "timeout" then
            log:error("Unable to renew IP")
            error("Unable to renew IP", 0)
            return -1
        end
    end

    local destIP = dest
    if type(dest) ~= "number" and not string.start(dest, "hw:") then
        -- dns request
        -- print("DNS resolve of "..dest.." started")
        local fc = string.sub(dest, 1, 1)
        if tonumber(fc) == nil then
            if dnsCache[dest] == nil then
                if addrTbl.dns == nil then
                    dnsCache[dest] = { ip = dest }
                else
                    sendMsg(10000, addrTbl.dns, { type = "net.dns.get" }, { domain = dest })
                    -- print("DNS resolve msg sent")
                    local msg = net.waitForMsgAdv(10000, 2, function(msg)
                        return msg.origin == addrTbl.dns and msg.header.type == "net.dns.get.return"
                    end)
                    if msg == "timeout" or msg.header.code == "not_found" then
                        return -1
                    end
                    dnsCache[dest] = msg.body
                end
            end
            destIP = dnsCache[dest].ip
            head.domain = dest
        else
            dest = net.ipToNumber(dest)
        end
        -- print(dest.." resolved to "..net.ipFormat(destIP))
    end

    if id == nil or id == -1 then
        msgId = msgId + 1
        id = msgId
    end
    

    if destIP == ipAddr then
        -- print('Doing loopback')
        local msg = {
            origin = ipAddr,
            dest = destIP,
            port = port,
            header = head,
            body = body,
            msgid = id,
        }
        -- print(net.stringMessage(msg))
        logVerboseMessage('send: ' .. net.stringMessage(msg))
        os.queueEvent("modem_message", 'loopback', port, port, msg, 0)
        return id
    end

    modem.open(port)

    body = encryptMsg(destIP, head, body)
    if (not body) and head.encrypted then
        log:warn('Encrypted message had no body')
        head.encrypted = nil
    end

    local msg = {
        origin = ipAddr,
        dest = destIP,
        port = port,
        header = head,
        body = body,
        msgid = id,
    }
    logVerboseMessage('send: ' .. net.stringMessage(msg))
    if ipAddr == 0x0 then
        msg.origin = "hw:" .. hwAddr
    end
    modem.transmit(port, port, msg)
    -- print("msg sent "..net.stringMessage(msg))
    -- print("msg sent to "..net.ipFormat(destIP).." of type "..head.type)
    return id
end

---Gets the IP address associated with a given hostname
---@param hostname string|NetAddress Hostname, IP address, or HW address
---@return NetAddress ip Numeric IP address or HW address
net.realizeHostname = function(hostname)
    if type(hostname) == 'number' or string.start(hostname, "hw:") then
        return hostname
    end
    local fc = string.sub(hostname, 1, 1)
    if tonumber(fc) == nil then
        if dnsCache[hostname] == nil then
            if addrTbl.dns == nil then
                dnsCache[hostname] = { ip = hostname }
            else
                sendMsg(10000, addrTbl.dns, { type = "net.dns.get" }, { domain = hostname })
                -- print("DNS resolve msg sent")
                local msg = net.waitForMsgAdv(10000, 2, function(msg)
                    return msg.origin == addrTbl.dns and msg.header.type == "net.dns.get.return"
                end)
                if msg == "timeout" or msg.header.code == "not_found" then
                    return -1
                end
                dnsCache[hostname] = msg.body
            end
        end
        return dnsCache[hostname].ip
    else
        return net.ipToNumber(hostname)
    end
end

---Waits for a message based on the check function, or a timeout.
---Timeout <= 0 disables timeout.
---Check function takes the port and message.
---Returns the message, or "timeout"
---@param check function Check function, takes port and message
---@param time number Timeout time in seconds
---@return table|string rsp Message or error string
local function waitForMsg(check, time)
    expect(1, check, "function")
    expect(2, time, "number")

    time = time or 2
    local cont = true
    for i, message in pairs(messages) do
        if not check(message.port, message.msg) then
            table.remove(messages, i)
            -- print("Message gotten from stored messages")
            return message.msg
        end
    end

    local timeout = -1
    if time > 0 then
        timeout = os.startTimer(time)
    end
    while cont do
        local event = { os.pullEvent() }
        if event[1] == "net_message" then
            local _, message = unpack(event)
            local port = message.port
            -- print(net.stringMessage(message))
            -- print("MSG "..net.ipFormat(message.origin).." '"..message.header.type.."'")
            if message.dest == ipAddr and message.origin == dhcpIP and message.header.type == "net.ip.renew.return" and message.body.action == "reget" then
                -- print("Getting IP address")
                local ipGetBody = {}
                if net.getHostname() ~= "" then
                    ipGetBody.hostname = net.getHostname()
                end
                ipAddr = 0x0
                leaseTime = 9e99
                sendMsg(10000, -1, { type = "net.ip.req" }, ipGetBody)
                if waitForMsg(function(rPort, msg)
                        if rPort ~= 10000 then return true end
                        if msg.dest == "hw:" .. hwAddr and msg.header.type == "net.ip.acp.return" then
                            os.cancelTimer(timeout)
                            return false
                        end
                        os.cancelTimer(timeout)
                        return true
                    end, 10) == "timeout" then
                    log:fatal("Failed to get IP address, Network module unavailable")
                    error("Failed to get IP address, Network module unavailable", 0)
                    os.cancelTimer(timeout)
                    return "network_error"
                end
            elseif message.dest == ipAddr or message.dest == "hw:" .. hwAddr or message.dest == -1 then
                local origin = message.origin
                if message.header.conId then
                    origin = origin .. message.header.conId
                end
                if message.header.publicKey then
                    if not remoteKeys[origin] then
                        remoteKeys[origin] = message.header.publicKey
                        logVerboseMessage('Storing public key for '..origin)
                    end
                end
                if message.header.encrypted and message.body and message.body.cipher then
                    log:warn('Late decrypt')
                    if remoteKeys[origin] == message.header.publicKey then
                        local suc, body = net.encrypt.decrypt(message.body.cipher, message.body.sig,
                            message.header.publicKey)
                        if suc then
                            message.body = body
                            log:debug('decrypted msg from ' .. net.ipFormat(message.origin))
                            print('decrypted msg from ' .. net.ipFormat(message.origin))
                        else
                            log:warn('Failed to decrypt msg from ' .. net.ipFormat(message.origin))
                            printError('Failed to decrypt msg from ' .. net.ipFormat(message.origin))
                        end
                    end
                end
                cont = check(port, message)
                if not cont then
                    os.cancelTimer(timeout)
                    -- print(net.stringMessage(message))
                    return message
                end
                table.insert(messages, { port = port, msg = message })
            end
        elseif event[1] == "timer" and event[2] == timeout then
            cont = false
            return "timeout"
        end
    end
    os.cancelTimer(timeout)
    return 'How did we get here?'
end

--- If messages that can not be decrypted should be ignored
net.ignoreMsgOnDecryptFail = true
local processedMessages = {}
local waitingForAccept = false
local osPullEventRaw = os.pullEventRaw
os.pullEventRaw = function(sFilter)
    -- print("Waiting . . .")
    -- if sFilter ~= nil then
    --     print("- For '"..sFilter.."'")
    -- end
    while true do
        local event = { osPullEventRaw() }
        if event[1] == "modem_message" then
            -- print("Got Modem Msg")
            local _, _, port, _, msg, _ = unpack(event)
            local ps, pe = pcall(function()
                if not net.validMsg(port, msg) then
                    return
                end
                ---@cast msg NetMessage
                
                local origin = msg.origin
                if msg.header.conId then
                    origin = origin .. msg.header.conId
                end
                if msg.header.originDomain then
                    origin = msg.header.originDomain ---@cast origin string
                end
                
                if processedMessages[origin .. msg.msgid] then -- we already determined that this message was bad
                    return
                end
                
                processedMessages[origin..msg.msgid] = true
                
                if msg.header.publicKey then
                    -- log:debug('Received message w/ public key')

                    if not remoteKeys[origin] then
                        remoteKeys[origin] = msg.header.publicKey
                    else
                        local eq = true
                        for i, v in pairs(remoteKeys[origin]) do
                            if msg.header.publicKey[i] ~= v then
                                eq = false
                                break
                            end
                        end
                        if not eq then
                            log:warn('Received message from ' .. origin .. ' but public key does to match cached version')
                            log:debug(textutils.serialiseJSON(remoteKeys[origin]))
                            log:debug('vs')
                            log:debug(textutils.serialiseJSON(msg.header.publicKey))
                            
                            -- prevent bad version of message from getting through
                            return
                        end
                    end

                    if msg.header.encrypted then
                        if not msg.body then
                            log:warn('Received message marked as encrypted from ' ..
                            net.ipFormat(msg.origin) .. ', but did not have body (msgid=' .. msg.msgid .. ')')
                        elseif not msg.body.cipher then
                            log:warn('Received message marked as encrypted from ' ..
                            net.ipFormat(msg.origin) .. ', but did not have cipher in body (msgid=' .. msg.msgid .. ')')
                        elseif not msg.body.sig then
                            log:warn('Received message marked as encrypted from ' ..
                            net.ipFormat(msg.origin) .. ', but did not have signature in body (msgid=' .. msg.msgid .. ')')
                        else
                            local suc, body = net.encrypt.decrypt(msg.body.cipher, msg.body.sig,
                                msg.header.publicKey)
                            if suc then
                                if not body then
                                    log:warn('Failed to decrypt msg from ' ..
                                        net.ipFormat(msg.origin) .. ', body was malformed')
                                    return
                                end
                                msg.body = body
                                logVerboseMessage('decrypted msg from ' .. net.ipFormat(msg.origin))
                                if msg.body.cipher then
                                    log:warn('Message had a cipher element in body')
                                end
                            else
                                log:warn('Failed to decrypt msg from ' .. net.ipFormat(msg.origin))
                                if net.ignoreMsgOnDecryptFail then return end
                            end
                        end
                    elseif msg.body and msg.body.cipher then
                        log:warn("Message had cipher body but was not encrypted")
                    end
                end

                if msg.dest == "hw:" .. hwAddr then
                    logVerboseMessage('recv: ' .. net.stringMessage(msg))
                    -- print("msg for hw '"..msg.header.type.."'")
                    if msg.header.type == "net.ip.acp.return" then
                        if waitingForAccept then
                            log:info('DHCP accept')
                            print("DHCP accept")
                            ipAddr = msg.body.ip
                            ipMask = msg.body.mask
                            leaseTime = msg.body.time
                            addrTbl = msg.body.addrTbl
                            dhcpIP = tonumber(msg.origin) or dhcpIP
                            waitingForAccept = false
                        else
                            -- print("Not waiting for accept return")
                        end
                    elseif msg.header.type == "net.ip.req.return" then
                        if ipAddr == 0x0 and not waitingForAccept then
                            waitingForAccept = true
                            -- ipAddr = msg.body.ip
                            -- ipMask = msg.body.mask
                            -- leaseTime = msg.body.time
                            log:info("Accepting IP offer of " ..
                                net.ipFormat(msg.body.ip) .. " from " .. net.ipFormat(msg.origin))
                            print("Accepting IP offer of " ..
                                net.ipFormat(msg.body.ip) .. " from " .. net.ipFormat(msg.origin))
                            -- print(net.stringMessage(msg))
                            -- net.reply(10000, msg, { type = "net.ip.acp" }, { hwAddr = hwAddr })
                            local hn = cfg.hostname ---@type string|nil
                            sendMsg(10000, msg.origin, { type = "net.ip.acp" }, { hwAddr = hwAddr })
                        else
                            -- print("already had IP or waiting on accept")
                        end
                    end
                    function msg:reply(p, head, body)
                        net.reply(p, self, head, body)
                    end

                    os.queueEvent("net_message", msg)
                    onMsg(msg)
                elseif msg.dest == ipAddr then
                    logVerboseMessage('recv: ' .. net.stringMessage(msg))
                    if port == net.standardPorts.network and msg.header.type == "ping" then
                        net.reply(net.standardPorts.network, msg, { type = "ping-return" }, {})
                        log:debug("Got pinged by " .. net.ipFormat(msg.origin))
                    end
                    if msg.header.type == "net.ip.check" then
                        net.reply(net.standardPorts.network, msg, { type = "net.ip.found" }, { hwAddr = hwAddr })
                    else
                        function msg:reply(p, head, body)
                            net.reply(p, self, head, body)
                        end

                        os.queueEvent("net_message", msg)
                        onMsg(msg)
                    end
                elseif msg.dest == -1 then
                    logVerboseMessage('recv: ' .. net.stringMessage(msg))
                    -- print("Broadcast MSG from "..net.ipFormat(msg.origin).." of type '"..msg.header.type.."'")
                    function msg:reply(p, head, body)
                        net.reply(p, self, head, body)
                    end

                    os.queueEvent("net_message", msg)
                    onMsg(msg)
                end
            end)
            if not ps then
                log:error(pe)
                printError(pe)
            end
        else
            -- print("Got "..event[1])
        end
        if sFilter == nil or sFilter == event[1] then
            return unpack(event)
        end
    end
end
os.pullEvent = function(sFilter)
    local event = { os.pullEventRaw(sFilter) }
    if event[1] == "terminate" then
        error("Terminating", 0)
    end
    return unpack(event)
end

-- +------------------------+
-- | Modem Helper Functions |
-- +------------------------+

---Get a modem on side, and add network functions
---@param side string Side of computer: <code>front</code>, <code>back</code>, <code>left</code>, <code>right</code>, <code>top</code>, <code>bottom</code>
---@return table|nil modem Model handle
net.getModem = function(side)
    expect(1, side, "string")

    if peripheral.getType(side) ~= "modem" then
        return nil
    end
    local mdm = peripheral.wrap(side)
    ---Send a message from the modem
    ---@param port number Network port for message (see net.standardPorts)
    ---@param dest number Destination hostname, IP address, or HW address
    ---@param head table Message head, should include type parameter
    ---@param body any Message Body
    ---@return number id Message ID
    function mdm:sendMsg(port, dest, head, body)
        expect(1, port, "number")
        expect(2, dest, "number")
        expect(3, head, "table")

        body = encryptMsg(dest, head, body)
        if (not body) and head.encrypted then
            log:warn('Encrypted message had no body')
            head.encrypted = nil
        end

        mdm.open(port)
        local id = net.useMsgId()

        local msg = {
            origin = ipAddr,
            dest = dest,
            port = port,
            header = head,
            body = body,
            msgid = id,
        }
        if ipAddr == 0x00000000 then
            msg.origin = hwAddr
        end
        self.transmit(port, port, msg)
        return id
    end

    ---Send a message from the modem
    ---@param port number Network port for message (see net.standardPorts)
    ---@param dest number Destination hostname, IP address, or HW address
    ---@param head table Message head, should include type parameter
    ---@param body any Message Body
    ---@param id number Message Id
    ---@return number id Message ID
    function mdm:sendMsgAdv(port, dest, head, body, id)
        expect(1, port, "number")
        expect(2, dest, "number")
        expect(3, head, "table")
        -- expect(4, body, "any")
        expect(5, id, "number")

        body = encryptMsg(dest, head, body)
        if (not body) and head.encrypted then
            log:warn('Encrypted message had no body')
            head.encrypted = nil
        end

        mdm.open(port)
        local msg = {
            origin = ipAddr,
            dest = dest,
            port = port,
            header = head,
            body = body,
            msgid = id,
        }
        if ipAddr == 0x0 then
            msg.origin = "hw:" .. hwAddr
        end
        self.transmit(port, port, msg)
        return id
    end

    ---Send a message from the modem <b>DOES NOT ENCRYPT</b>
    ---@param port number Network port for message (see net.standardPorts)
    ---@param origin number Numeric IP or HW address to indicate as message origin
    ---@param dest number Destination hostname, IP address, or HW address
    ---@param head table Message head, should include type parameter
    ---@param body any Message Body
    ---@param id number Message Id
    ---@return number id Message ID
    function mdm:sendMsgAdv2(port, origin, dest, head, body, id)
        expect(1, port, "number")
        expect(2, origin, "number")
        expect(3, dest, "number")
        expect(4, head, "table")
        expect(6, id, "number")

        -- body = encryptMsg(dest, head, body)
        -- if (not body) and head.encrypted then
        --     log:warn('Encrypted message had no body')
        --     head.encrypted = nil
        -- end

        mdm.open(port)
        local msg = {
            origin = origin,
            dest = dest,
            port = port,
            header = head,
            body = body,
            msgid = id,
        }
        -- if ipAddr == 0x0 then
        --     msg.origin = "hw:"..hwAddr
        -- end
        self.transmit(port, port, msg)
        return id
    end

    return mdm
end

-- +--------------------+
-- | Hostname functions |
-- +--------------------+

---Returns the network hostname of the computer
---@return string hostname Current hostname (defaults to "")
net.getHostname = function()
    return cfg.hostname
end

---Sets the network hostname of the computer. Requires sudo.
---Returns if setting the hostname succeeded
---@param new string New hostname
---@return boolean suc If the hostname was set successfully
net.setHostname = function(new)
    expect(1, new, "string")

    cfg.hostname = new
    -- local f = fs.open(cfgPath, "w")
    -- if f == nil then
    --     log:error("Unable to change hostname")
    --     error("Unable to change hostname", 0)
    --     return false
    -- end
    -- f.write(textutils.serialiseJSON(cfg))
    -- f.close()
    config:save()
    sendMsg(10000, 0xC0A80000, { type = "net.ip.changeHost" }, { hostname = new })
    return true
end

-- +----------------+
-- | Setup function |
-- +----------------+

-- If the network module has been setup
local isSetup = false

---If the network module has been setup
---@return boolean setup if module is setup
net.isSetup = function()
    return isSetup
end
---Gets the currently used modem
---@return table|nil modem Current primary modem
net.getCModem = function()
    return modem
end

---Setup the network module, returns false on a failure
---@param mdm table|nil Primary modem (optional)
---@param ip number|nil Numeric IP address (optional)
---@return boolean setup If the module is not setup
net.setup = function(mdm, ip)
    expect(1, mdm, "table", "nil")
    expect(1, ip, "number", "nil")

    if isSetup then return true end
    if not fs.exists(hwAddrPath) then
        hwAddr = string.randomString(16, { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f' })
        local f = fs.open(hwAddrPath, "w")
        if f == nil then
            log:error("Failed to write Hardware Address, Network module unavailable")
            error("Failed to write Hardware Address, Network module unavailable", 0)
            return false
        end
        f.write(hwAddr)
        f.close()
    else
        local f = fs.open(hwAddrPath, "r")
        if f == nil then
            log:error("Failed to read Hardware Address, Network module unavailable")
            error("Failed to read Hardware Address, Network module unavailable", 0)
            return false
        end
        hwAddr = f.readAll()
        f.close()
    end

    if mdm == nil then
        local modems = { peripheral.find("modem", function(name, test)
            return test.isWireless()
        end) }
        if #modems == 0 then
            modems = { peripheral.find("modem"), }
            if #modems == 0 then
                log:error("No Modem Attached")
                error("No Modem Attached", 0)
                return false
            end
        end
        modem = modems[1]
    else
        modem = mdm
    end

    if ip == nil then
        local ipGetBody = {}
        if cfg.hostname ~= "" then
            ipGetBody.hostname = cfg.hostname
        end
        for i = 1, 3 do
            -- print("Getting IP")
            sendMsg(10000, -1, { type = "net.ip.req" }, ipGetBody)
            if waitForMsg(function(port, msg)
                    if port ~= 10000 then return true end
                    if msg.dest == "hw:" .. hwAddr and msg.header.type == "net.ip.acp.return" then
                        return false
                    end
                    return true
                end, 10) == "timeout" then
                log:error("Failed to get IP address, Trying again in 30 seconds")
                -- return false
            else
                log:info('Got IP address: ' .. net.ipFormat(ipAddr))
                break
            end
            os.sleep(30)
        end
        if type(ipAddr) ~= "number" or ipAddr < 0 then
            print(ipAddr)
            ipAddr = -1
            log:error("Failed to get IP address, Network module unavailable")
            error("Failed to get IP address, Network module unavailable", 0)
            return false
        end
    else
        ipAddr = ip
    end

    for _, port in pairs(net.standardPorts) do
        net.open(port)
    end

    isSetup = true
    return true
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
    expect(1, port, "number")
    expect(2, dest, "number", "string")
    expect(3, msgType, "string")

    if not net.setup() then
        return -1
    end
    local head = {
        type = msgType
    }
    return sendMsg(port, dest, head, body)
end
---Send a message with a type header, and waits for the reply.
---Returns the message, "setup_fail", "sent_fail", or "timeout" after 2 seconds
---@param port number Network port for message (see net.standardPorts)
---@param dest NetAddress|string Destination IP address, HW address, or hostname
---@param msgType string Message type
---@param body any Message body
---@return NetMessage|string rsp Response message, or error string
net.sendSync = function(port, dest, msgType, body)
    expect(1, port, "number")
    expect(2, dest, "number", "string")
    expect(3, msgType, "string")

    if not net.setup() then
        return "setup_fail"
    end
    net.open(port)
    local head = {
        type = msgType
    }
    local id = sendMsg(port, dest, head, body)
    if id == -1 then
        return "send_fail"
    end
    log:debug(("Waiting for reply w/ id `%d`"):format(id))
    return waitForMsg(function(rPort, message)
        if rPort ~= port then
            log:debug(('p `%d` != `%d`'):format(rPort, port))
            return true
        end
        if message.dest == ipAddr then
            if message.msgid == id then
                log:debug('- Found message')
                return false
            else
                log:debug(('i `%d` != `%d`'):format(message.msgid, id))
            end
        else
            log:debug(('d `%s` != `%s`'):format(message.dest, ipAddr))
        end
        return true
    end, 2)
end

---Send a message with a custom header. Header should include a 'type' parameter.
---@param port number Network port for message (see net.standardPorts)
---@param dest NetAddress|string Destination IP address, HW address, or hostname
---@param head NetMessage.Header Message header, should include type parameter
---@param body any Message body
---@return number id Message ID or -1 on error
net.sendAdv = function(port, dest, head, body)
    expect(1, port, "number")
    expect(2, dest, "number", "string")
    expect(3, head, "table")

    if not net.setup() then
        return -1
    end
    net.open(port)
    return sendMsg(port, dest, head, body)
end
---Send a message with a custom header, and waits for the reply. Header should include a 'type' parameter.
---Returns the message, "setup_fail", "send_fail", or "timeout" after 2 seconds
---@param port number Network port for message (see net.standardPorts)
---@param dest NetAddress|string Destination IP address, HW address, or hostname
---@param head NetMessage.Header Message header, should include type parameter
---@param body any Message body
---@return NetMessage|string rsp Response message, or error string
net.sendAdvSync = function(port, dest, head, body)
    expect(1, port, "number")
    expect(2, dest, "number", "string")
    expect(3, head, "table")

    if not net.setup() then
        return "setup_fail"
    end
    net.open(port)
    local id = sendMsg(port, dest, head, body)
    if id == -1 then
        return "send_fail"
    end
    log:debug(("Waiting for reply w/ id `%d`"):format(id))
    return waitForMsg(function(rPort, message)
        if rPort ~= port then
            log:debug(('p `%d` != `%d`'):format(rPort, port))
            return true
        end
        -- if message.header == head and message.body == body then return true end
        if message.dest == ipAddr then
            if message.msgid == id then
                log:debug('- Found message')
                return false
            else
                log:debug(('i `%d` != `%d`'):format(message.msgid, id))
            end
        else
            log:debug(('d `%s` != `%s`'):format(message.dest, ipAddr))
        end
        return true
    end, 2)
end

---Reply to a message
---@param port number Network port for reply (see net.standardPorts)
---@param old NetMessage Message object to reply to
---@param head NetMessage.Header Reply header, should include type parameter
---@param body any Reply body
---@return number id Reply id
net.reply = function(port, old, head, body)
    expect(1, port, "number")
    expect(2, old, "table")
    expect(3, head, "table")

    if not net.setup() then
        return -1
    end
    net.open(port)
    if old.header.conId then head.destConId = old.header.conId end
    if old.header.domain then head.originDomain = old.header.domain end
    head.publicKey = nil
    return sendMsg(port, old.origin, head, body, old.msgid)
end

-- +----------------+
-- | Wait functions |
-- +----------------+

---Waits for a message on a particular port, with a timeout. Default timeout is 2 seconds.
---@param port number Network port to listen on (-1 for any)
---@param time number Timeout in seconds
---@return string|NetMessage rsp Message or error string
net.waitForMsg = function(port, time)
    expect(1, port, "number")
    expect(2, time, "number")

    if not net.setup() then
        return "setup_fail"
    end
    net.open(port)
    return waitForMsg(function(rPort, msg)
        if rPort ~= port then return true end
        if msg.dest ~= ipAddr then return true end
        return false
    end, time)
end

---Waits for a message on a particular port, with a timeout. Default timeout is 2 seconds.
---Check function should return true on the message you want, and takes the message as a parameter.
---@param port number Network port to listen on (-1 for any)
---@param time number Timeout in seconds
---@param check function Message check function, takes message as parameter, and returns continue waiting
---@return string|NetMessage rsp Message or error string
net.waitForMsgAdv = function(port, time, check)
    expect(1, port, "number")
    expect(2, time, "number")
    expect(3, check, "function")

    if not net.setup() then
        return "setup_fail"
    end
    net.open(port)
    return waitForMsg(function(rPort, msg)
        if rPort ~= port then return true end
        if msg.dest ~= ipAddr then return true end
        return not check(msg)
    end, time)
end

---Waits for any message with a continue check function and timeout
net.waitForMsgAll = waitForMsg

---Checks is a modem message is a valid network message
---@param port number Network port of message
---@param message table Message to validate
---@return boolean valid Message is valid
net.validMsg = function(port, message)
    expect(1, port, "number")
    -- expect(2, message, "any")
    if type(message) ~= "table" then return false end
    if port < 10000 or port > 20000 then return false end
    if message.dest == -1 then
        return true
    end
    if message.dest == ipAddr then
        return true
    end
    if ipAddr == 0x0 and message.dest == "hw:" .. hwAddr then
        return true
    end
    return false
end

---Register a message handler
---@param func function Handler function, takes a message object
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
---@param port  number Network port to open (see net.standardPorts)
net.open = function(port)
    expect(1, port, "number")

    if modem then modem.open(port) end
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
    local time = os.time()
    local rt = net.sendSync(net.standardPorts.network, dest, "ping", {})
    if type(rt) ~= "table" then
        log:error('Error pinging ' .. net.ipFormat(net.realizeHostname(dest)) .. ': ' .. rt)
        error('Error pinging ' .. net.ipFormat(net.realizeHostname(dest)) .. ': ' .. rt, 0)
        return
    end
    local elapsed = os.time() - time
    log:debug("Received return from " .. net.ipFormat(net.realizeHostname(dest)) .. " after " .. elapsed .. "s")
    print("Received return from " .. net.ipFormat(net.realizeHostname(dest)) .. " after " .. elapsed .. "s")
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

---Sets if the net module should log all messages
---@param vb boolean If all messages should be logged
net.setLogVerbose = function(vb)
    logVerboseMessages = vb
end

shell.setAlias('net', '/os/net/cmd.lua')

---@alias NetAddress number|string IP or HW address

---@class NetMessage Networking message struct
---@field origin NetAddress Origin IP or HW of the message
---@field dest NetAddress Destination IP or HW of message
---@field port number Networking port for message
---@field header NetMessage.Header Header table
---@field body nil|table|string Message body
---@field msgid number Message ID
---@field reply function Reply to this message

---@class NetMessage.Header Networking message header table
---@field type string Net message type
---@field encrypted boolean|nil If the message body is encrypted
---@field publicKey byteArray|nil Body encryption public key
---@field domain string|nil Destination domain name
---@field conId number|nil NAT connection ID
---@field destConId number|nil Destination NAT connection ID
---@field originDomain string|nil (REPLY ONLY) Domain the request was sent to