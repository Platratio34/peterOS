---@class NetInterface
---@field package __id number
---@field name string
---@field private __modem ModemPeripheral
---@field private __modemSide string
---@field private __log Logger
---@field private __ip number?
---@field private __subnetMask number?
---@field private __ipLeaseExpire number?
---@field private __hwAddress string
---@field private __hostname string?
---@field private __remoteKeys table<string, string|byteArray>
---@field private __waitingMsgs NetMessage[]
---@field private __handlerId number?
---@field private __openPorts table<number, boolean>
---@field private __alreadyProcessed table<string, boolean>
---@field private __waitingForIPAccept boolean
---@field private __waitingForRenew number
---@field private __dnsCache table<string, DHCP.DNSRecord>
---@field private __dhcpIP number?
---@field private __config NetInterface.Config
---@field private __msgHandlers table<number, fun(msg: NetMessage)>
---@field private __msgHandlerId number
---@field private __multicastSubscribers table<string, table<string, fun(ip: number, msg: NetMessage)>>
---@field private __multicastSubscriberCounts table<string, number>
local NetInterface = {
    _config = {
        respondToPing = true
    },
    __msgHandlerId = 0
}

local NetInterfaceMT = {
    __index = NetInterface,
    type = 'NetInterface'
}

---@class NetInterface.Config
---@field respondToPing boolean
---@field hostname string?
---@field originHostname string?
---@field receiveAll boolean?

local interfaceNumber = 0
local msgId = os.epoch('utc') ---@type number

local HW_ADDRESS_PATH = '/hw.addr'

---@param name string?
---@param modem ModemPeripheral|string|nil
---@param ip string|number|nil
---@param hwAddress string?
---@return NetInterface interface
function _G.net.NetInterface(name, modem, ip, hwAddress)
    local o = {}
    setmetatable(o, NetInterfaceMT) ---@cast o NetInterface
    o.__id = interfaceNumber
    interfaceNumber = interfaceNumber + 1
    o:__init__(name, modem, ip, hwAddress)
    return o
end

---@package
---@param name string?
---@param modem ModemPeripheral|string|nil
---@param ip string|number|nil
---@param hwAddress string?
function NetInterface:__init__(name, modem, ip, hwAddress)
    name = name or ('net_' .. self.id)
    self.name = name
    self.log = pos.Logger(('net_interface_%s.log'):format(name))

    if modem == nil then
        local modems = { peripheral.find("modem", function(_, test)
            return test.isWireless()
        end) } ---@cast modems ModemPeripheral[]
        if #modems == 0 then
            modems = { peripheral.find("modem") }
            if #modems == 0 then
                self.log:error("No Modem Attached")
                error("No Modem Attached", 3)
            end
        end
        modem = modems[1]
    elseif type(modem) == 'string' then
        local side = modem
        modem = peripheral.wrap(side)
        if not modem then
            self.log:error('Not modem attached to side %s', side)
            error(('Not modem attached to side %s'):format(side), 3)
        end
        ---@cast modem ModemPeripheral
    end
    self.__modemSide = peripheral.getName(modem)
    self.__modem = modem --[[@as ModemPeripheral]]

    if hwAddress then
        self.__hwAddress = hwAddress
    else
        if not fs.exists(HW_ADDRESS_PATH) then
            self.__hwAddress = NetInterface.generateHWAddress()
            local f = fs.open(HW_ADDRESS_PATH, "w")
            if f == nil then
                self.log:error("Failed to write Hardware Address, Network interface %s unavailable", name)
                error(("Failed to write Hardware Address, Network interface %s unavailable"):format(name), 3)
            end
            f.write(self.__hwAddress)
            f.close()
        else
            local f = fs.open(HW_ADDRESS_PATH, "r")
            if f == nil then
                self.log:error("Failed to read Hardware Address, Network interface %s unavailable", name)
                error(("Failed to read Hardware Address, Network interface %s unavailable"):format(name), 3)
            end
            self.__hwAddress = f.readAll()
            f.close()
        end
    end

    if ip then
        self.__ip = net.ipToNumber(ip) --[[@as number]]
    end

    self.__waitingMsgs = {}
    self.__openPorts = {}
    self.__alreadyProcessed = {}
    self.__dnsCache = {}
    self.__msgHandlers = {}
    self.__multicastSubscribers = {}
    self.__multicastSubscriberCounts = {}

    self.__handlerId = pos.addEventHandler(function(event, handler) self:__onModemMessage(event) end, 'modem_message',
        name .. '_mmHandler')
    
    self.log:info('Interface %s created', name)
end

---Set the config options for this interface
---@param config string|NetInterface.Config
function NetInterface:setConfig(config)
    expect(1, config, 'string', 'table')
    if type(config) == 'string' then
        local configPath = config
        local f = fs.open(configPath, 'r')
        if not f then
            self.log:error('Unable to load config from: %s; unable to open file', configPath)
            error('Unable to load config from: '..configPath..'; Unable to open file')
        end
        config = textutils.unserialiseJSON(f.readAll())
        f.close()
        if not config then
            self.log:error('Unable to load config from: %s; Config corrupted', configPath)
            return
        end
    end
    self.__config = config
    self.log:info('Config set')
end

function NetInterface.generateHWAddress()
    return string.randomString(16, { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f' })
end

---@private
---@param dest NetAddress
---@param header NetMessage.Header
---@param body table|string|nil
function NetInterface:__encryptMsg(dest, header, body)
    expect(1, dest, 'string', 'number')
    expect(2, header, 'table')
    expect(3, body, 'table', 'string')
    if header.publicKey and header.encrypted then -- message is probably already encrypted
        return body
    end

    local destIPC = dest
    if header.domain then
        destIPC = header.domain
    elseif header.conId then
        destIPC = destIPC .. header.conId
    end

    header.publicKey = net.encrypt.getPublicKey()

    if body and self.__remoteKeys[destIPC] then
        local cipher, sig = net.encrypt.encrypt(body, self.__remoteKeys[destIPC])
        body = {
            cipher = cipher,
            sig = sig
        }
        header.encrypted = true
    end
    return body
end

---Get the the Id of the most recent sent message
---@return number msgId
function NetInterface:getMsgId()
    return msgId
end

---Increment the message ID counter and return the value
---@return number msgId
function NetInterface:useMsgId()
    msgId = msgId + 1
    return msgId
end

---@private
---@param port number
---@param dest NetAddress|string
---@param header table
---@param body table|string|nil
---@param id number?
---@return number msgId
function NetInterface:__sendMsg(port, dest, header, body, id)
    expect(1, port, 'number')
    expect(2, dest, 'number', 'string')
    expect(3, header, 'table')
    expect(4, body, 'string', 'table')
    expect(5, id, 'number', 'nil')

    if self.__ipLeaseExpire and self.__ipLeaseExpire < os.epoch('utc') + (8.64e7 * 3) then
        if not self.__waitingForRenew then
            local msg = { ---@type NetMessage
                origin = self.__ip,
                dest = self.__dhcpIP,
                port = net.standardPorts.network,
                header = { type = 'net.ip.renew', publicKey = net.encrypt.getPublicKey() },
                body = { hwaddr = self.__hwAddress },
                msgid = self:useMsgId(),
                reply = function() end
            }
            self.__modem.transmit(msg.port, msg.port, msg)
        elseif self.__waitingForRenew + 1000 * 30 < os.epoch('utc') then
            self.log:warn('Unable to renew IP address')
            self.__waitingForRenew = nil
        end
    end

    local destIP = dest
    if type(dest) == 'string' and not dest:start('hw:') then
        local ip = self:resolveHostname(dest)
        if ip == -1 then
            return -1
        end
        destIP = ip
    end

    if id == nil or id == -1 then
        id = self:useMsgId()
    end

    if self.__config.originHostname and not header.originDomain then
        header.originDomain = self.__config.originHostname
    end

    local msg = {
        origin = self.__ip or self.__hwAddress,
        dest = destIP,
        port = port,
        header = header,
        body = body,
        msgid = id
    }

    if destIP == self.__ip or destIP == self.__hwAddress then
        self:__onMsg(msg)
        return id
    end

    msg.body = self:__encryptMsg(destIP, header, body)
    net.certificate.addCert(msg)

    self:open(port)
    self.__modem.transmit(port, port, msg)
    return id
end

---Wait for a message matching criteria
---@param port number? Port of message
---@param check nil|fun(port: number, msg: NetMessage): boolean Check function, returns `false` on message you want
---@param timeout number? Timeout (`-1` to disable, defaults to `net.DEFAULT_TIMEOUT`)
---@return NetMessage|string msg
function NetInterface:waitForMessage(port, check, timeout)
    if port then
        self:open(port)
    end

    for i, msg in pairs(self.__waitingMsgs) do
        if not port or (msg.port == port) then
            if check and not check(msg.port, msg) then
                table.remove(self.__waitingMsgs, i)
                return msg
            end
        end
    end

    timeout = timeout or net.DEFAULT_TIMEOUT
    if timeout > 0 then
        timeout = os.startTimer(timeout)
    else
        timeout = nil
    end

    while true do
        local event = { pos.pullEvent() }
        if event[1] == 'timer' and event[2] == timeout then
            return 'timeout'
        elseif event[1] == 'modem_message' then
            -- local _, side, rPort, _, msg = unpack(event)
            -- if not port or (msg.port == port) then
            --     if check and not check(msg.port, msg) then
            --         table.remove(self.__waitingMsgs, i)
            --         return msg
            --     end
            -- end
        end
    end
end

---Setup this interface and acquire IP if not pre-set
---@return boolean isSetup
function NetInterface:setup()
    self:open(net.standardPorts.network)
    if not self.__ip then
        local ipGetBody = {}
        if self.__config.hostname ~= "" then
            ipGetBody.hostname = self.__config.hostname
        end
        for i = 1, 3 do
            self:__sendMsg(10000, -1, { type = "net.ip.req" }, ipGetBody)
            if self:waitForMessage(net.standardPorts.network, function(port, msg)
                    if msg.dest == "hw:" .. self.__hwAddress and msg.header.type == "net.ip.acp.return" then
                        return false
                    end
                    return true
                end, 10) == "timeout" then
                self.log:error("Failed to get IP address, Trying again in 30 seconds")
                -- return false
            else
                self.log:info('Got IP address: ' .. net.ipFormat(self.__ip))
                break
            end
            os.sleep(30)
        end
        if not self.__ip or type(self.__ip) == 'number' then
            self.__ip = nil
            self.log:error("Failed to get IP address, Network module unavailable")
            error("Failed to get IP address, Network module unavailable", 0)
            return false
        end
    end
    return true
end

---@param port number
function NetInterface:open(port)
    expect(1, port, 'number')
    self.__modem.open(port)
    self.__openPorts[port] = true
end

---@private
---@param port number
function NetInterface:close(port)
    expect(1, port, 'number')
    self.__modem.close(port)
    self.__openPorts[port] = nil
end

---Check if a given message is valid for this interface
---@param port number
---@param msg any
---@return boolean isValid
function NetInterface:validMsg(port, msg)
    expect(1, port, 'number')
    if type(msg) ~= "table" then
        return false
    end
    if port < 10000 or port > 20000 then
        return false
    end
    if not self.__openPorts[port] then
        return false
    end

    if msg.dest == -1 or msg.dest == 0xffffffff then -- Broadcast
        return true
    end

    if self:isSubscribedTo(msg.dest) then -- Multicast
        return true
    end
    if msg.dest == self.__ip then -- Unicast
        return true
    end
    if msg.dest == "hw:" .. self.__hwAddress then -- Hardware Address
        return true
    end
    if self.__config.receiveAll then
        return true
    end
    return false
end

---@private
function NetInterface:__onModemMessage(event)
    local _, side, port, _, msg = unpack(event)
    if side ~= self.__modemSide then
        return
    end
    if not self:validMsg(port, msg) then
        return
    end

    ---@cast msg NetMessage

    local origin = msg.origin .. '' ---@type string
    if msg.header.rspDomain then
        origin = msg.header.rspDomain
    elseif msg.header.originDomain then
        origin = msg.originDomain
    elseif msg.header.conId then
        origin = origin .. msg.header.conId
    end

    if self.__alreadyProcessed[origin] then
        return
    end
    self.__alreadyProcessed[origin] = true

    if msg.header.publicKey or msg.header.certificate then
        local oPK = net.certificate.getKey(msg)

        if not oPK then
            if msg.header.certificate then
                self.log:warn('Received message with certificate from ' ..
                    net.ipFormat(msg.origin) .. ', but could not validate (msgid=' .. msg.msgid .. ')')
            else
                self.log:warn('Received message marked as encrypted from ' ..
                    net.ipFormat(msg.origin) .. ', but could not validate key (msgid=' .. msg.msgid .. ')')
            end
            return
        end

        if (msg.header.publicKey and msg.header.certificate) and (not net.encrypt.keyMatch(msg.header.publicKey, oPK)) then
            self.log:warn('Received message from ' .. origin .. ' but provided key does to match certificate')
            self.log:debug(textutils.serialiseJSON(msg.header.publicKey))
            self.log:debug('vs')
            self.log:debug(textutils.serialiseJSON(oPK))
            return
        end

        if (not self.__remoteKeys[origin]) or msg.header.certificate then
            self.__remoteKeys[origin] = oPK
        elseif not net.encrypt.keyMatch(oPK, self.__remoteKeys[origin]) then
            self.log:warn('Received message from ' .. origin .. ' but provided key does to match cached version')
            self.log:debug(textutils.serialiseJSON(self.__remoteKeys[origin]))
            self.log:debug('vs')
            self.log:debug(textutils.serialiseJSON(oPK))
            -- prevent bad version of message from getting through
            return
        end

        if msg.header.encrypted then
            if not msg.body then
                self.log:warn('Received message marked as encrypted from ' ..
                    net.ipFormat(msg.origin) .. ', but did not have body (msgid=' .. msg.msgid .. ')')
            elseif not msg.body.cipher then
                self.log:warn('Received message marked as encrypted from ' ..
                    net.ipFormat(msg.origin) .. ', but did not have cipher in body (msgid=' .. msg.msgid .. ')')
            elseif not msg.body.sig then
                self.log:warn('Received message marked as encrypted from ' ..
                    net.ipFormat(msg.origin) .. ', but did not have signature in body (msgid=' .. msg.msgid .. ')')
            else
                local suc, body = net.encrypt.decrypt(msg.body.cipher, msg.body.sig, oPK)
                if suc then
                    if not body then
                        self.log:warn('Failed to decrypt msg from ' ..
                            net.ipFormat(msg.origin) .. ', body was malformed')
                        return
                    end
                    msg.body = body
                    if msg.body.cipher then
                        self.log:warn('Message had a cipher element in body')
                    end
                else
                    self.log:warn('Failed to decrypt msg from ' .. net.ipFormat(msg.origin))
                    if net.ignoreMsgOnDecryptFail then return end
                end
            end
        elseif msg.body and msg.body.cipher then
            self.log:warn("Message had cipher body but was not encrypted")
        end
    end

    local interface = self
    function msg:reply(p, head, body)
        interface:reply(p, self, head, body)
    end

    if msg.dest == 'hw:' .. self.__hwAddress then
        if msg.header.type == 'net.ip.acp.return' then
            if self.__waitingForIPAccept then
                self.log:info('DHCP accept')
                self.__ip = msg.body.ip
                self.__subnetMask = msg.body.mask
                self.__ipLeaseExpire = msg.body.time

                self.__dhcpIP = msg.origin --[[@as number]]

                self.__waitingForIPAccept = false
                return
            end
        elseif msg.header.type == 'net.ip.req.return' then
            if not self.__ip and not self.__waitingForIPAccept then
                self.__waitingForIPAccept = true

                self.log:info("Accepting IP offer of " ..
                    net.ipFormat(msg.body.ip) .. " from " .. net.ipFormat(msg.origin))

                msg:reply(net.standardPorts.network, { type = 'net.ip.acp' }, { hwAddr = self.__hwAddress })
                return
            end
        end

        self:__onMsg(msg)
    elseif msg.dest == self.__ip then
        if port == net.standardPorts.network and msg.header.type == "ping" and self.__config.respondToPing then
            net.reply(net.standardPorts.network, msg, { type = "ping-return" }, {})
            self.log:debug("Got pinged by " .. net.ipFormat(msg.origin))
        end

        if msg.header.type == "net.ip.check" then
            net.reply(net.standardPorts.network, msg, { type = "net.ip.found" }, { hwAddr = self.__hwAddress })
            return
        elseif msg.header.type == 'net.ip.renew.return' and msg.origin == self.__dhcpIP then
            if msg.body.action == 'renewed' then
                self.__ip = msg.body.ip
                self.__subnetMask = msg.body.mask
                self.__ipLeaseExpire = msg.body.time
                self.__waitingForRenew = nil
                self.log:info('Renewed IP address')
                return
            end
        else
            self:__onMsg(msg)
        end
    elseif msg.dest == -1 or msg.dest == 0xffffffff then -- TODO: include lan broadcast?
        self:__onMsg(msg)
    elseif self:isSubscribedTo(msg.origin) then
        -- TODO: multicast
    end
end

---@private
---@param msg NetMessage
function NetInterface:__onMsg(msg)
    os.queueEvent(net.NET_MESSAGE_EVENT, msg, self.name)

    for id, handler in pairs(self.__msgHandlers) do
        local suc, error = pcall(handler, msg)
        if not suc then
            self.log:warn('Error in msg handler: %s', error)
        end
    end
end

---Checks if this interface is subscribed to the specified ip address
---@param ip NetAddress IP address to change
---@return boolean isSubscribedTo
function NetInterface:isSubscribedTo(ip)
    if type(ip) ~= 'number' then
        return false
    elseif ip < 0xe0000000 or ip > 0xefffffff then
        return false
    end
    return self.__multicastSubscriberCounts[ip .. ''] and self.__multicastSubscriberCounts[ip .. ''] > 0
end

---Get the DNS record for a given hostname
---@param hostname string
---@return DHCP.DNSRecord? record
function NetInterface:getDNSRecord(hostname)
    local dnsRecord = self.__dnsCache[hostname] ---@type DHCP.DNSRecord?
    if dnsRecord then
        if dnsRecord.time + dnsRecord.ttl < os.epoch('utc') then
            dnsRecord = nil
        end
    end
    
    if not dnsRecord then
        self:__sendMsg(net.standardPorts.network, self.__dhcpIP, { type = 'net.dns.get' }, { domain = hostname })
        local msg = self:waitForMessage(net.standardPorts.network, function(port, msg)
            return msg.origin == self.__dhcpIP and msg.header.type == 'net.dns.get.return'
        end, net.DEFAULT_TIMEOUT)
        if msg == 'timeout' then
            self.log:warn('Unable to resolve hostname "%s"; no response from DNS', hostname)
            return nil
        elseif msg.header.code == 'not_found' then
            self.log:warn('Unable to resolve hostname "%s"', hostname)
            return nil
        end
        dnsRecord = msg.body.record ---@type DHCP.DNSRecord
        self.__dnsCache[hostname] = dnsRecord
    end

    if not dnsRecord then
        self.log:warn('Unable to resolve hostname "%s"', hostname)
        return nil
    end

    return dnsRecord
end

---Resolve a hostname to an IP address
---@param hostname NetAddress|string
---@return NetAddress ip Resolved IP address **OR** `-1` on resolve failure
function NetInterface:resolveHostname(hostname)
    expect(1, hostname, 'string', 'number')
    if type(hostname) == 'number' then
        return hostname
    end
    ---@cast hostname string
    if hostname:start('hw:') then
        return hostname
    end

    local record = self:getDNSRecord(hostname)
    if not record then
        return -1
    end
    if record.type == 'A' then
        return record.ip
    elseif record.type == 'CNAME' or record.type == 'NS' then
        return self:resolveHostname(record.pointer)
    end

    self.log:error('Tried to resolve hostname, but received unknown record type: "%s"', record.type)
    return -1
end

---Increment the message handler counter, and return the value
---@private
---@return number handlerId
function NetInterface:__useHandlerId()
    local id = self.__msgHandlerId
    self.__msgHandlerId = self.__msgHandlerId + 1
    return id
end

---Add a message handler to this network interface
---@param handler fun(msg: NetMessage)
---@return integer handlerId
function NetInterface:addMsgHandler(handler)
    local id = self:__useHandlerId()
    self.__msgHandlers[id] = handler
    return id
end

---Remove a message handler from this network interface
---@param id number ID from `NetInterface:addMsgHandler()`
function NetInterface:removeMsgHandler(id)
    self.__msgHandlers[id] = nil
end

---Subscribe to a multicast group. IP must be between `224.0.0.0` (`0xe0000000`) and `239.255.255.255` (`0xefffffff`).
---@param ip number Multicast group IP
---@param handler fun(ip: number, msg: NetMessage) Multicast message handler
---@return integer id Handler Id, used to unregister subscriber
function NetInterface:multicastSubscribe(ip, handler)
    expect(1, ip, 'number')
    expect(2, handler, 'function')
    if ip < 0xe0000000 or ip > 0xefffffff then
        error(
            ('Invalid IP for multicast: %s. It must be between 224.0.0.0 and 239.255.255.255'):format(net.ipFormat(ip)),
            2)
    end
    local id = self:__useHandlerId()
    local ipStr = ip .. ''

    if not self.__multicastSubscribers[ipStr] then
        self.__multicastSubscribers[ipStr] = {}
    end
    self.__multicastSubscribers[ipStr][id] = handler

    if not self.__multicastSubscriberCounts[ipStr] then
        self.__multicastSubscriberCounts[ipStr] = 0
    end
    self.__multicastSubscriberCounts[ipStr] = self.__multicastSubscriberCounts[ipStr] + 1

    return id
end

---Remove a multicast subscription, uses ID from subscription
---@param ip number Multicast group IP
---@param id integer Handler Id, from `net.multicastSubscribe(ip, handler)`
function NetInterface:multicastUnsubscribe(ip, id)
    expect(1, ip, 'number')
    expect(2, id, 'number')
    if ip < 0xe0000000 or ip > 0xefffffff then
        error(
            ('Invalid IP for multicast: %s. It must be between 224.0.0.0 and 239.255.255.255'):format(net.ipFormat(ip)),
            2)
    end
    local ipStr = ip .. ''

    if self.__multicastSubscribers[ipStr] then
        self.__multicastSubscribers[ipStr][id] = nil
    end

    if self.__multicastSubscriberCounts[ipStr] then
        self.__multicastSubscriberCounts[ipStr] = self.__multicastSubscriberCounts[ipStr] - 1
    end
end

---Get the IP of this interface, may be nil if interface is not setup
---@return number? ip
function NetInterface:getIp()
    return self.__ip
end

---Get the Hardware Address of this interface
---@return string hwAddress
function NetInterface:getHWAddress()
    return self.__hwAddress
end

---Get the hostname of this network interface
---@return string? hostname
function NetInterface:getHostname()
    return self.__config.hostname
end

---Get the modem this interface uses
---@return ModemPeripheral modem
function NetInterface:getModem()
    return self.__modem
end

---Send a message over this interface
---@param port number Network port for message (see net.standardPorts)
---@param dest NetAddress|string Destination IP address, HW address, or hostname
---@param msgType string Message type
---@param body table|string|nil Message body
---@return integer msgId Message ID or -1 on error
function NetInterface:send(port, dest, msgType, body)
    expect(1, port, 'number')
    expect(2, dest, 'number', 'string')
    expect(3, msgType, 'string')
    expect(4, body, 'table', 'string')

    if not self:setup() then
        return -1
    end

    if net.isIPV4(dest) then
        dest = net.ipToNumber(dest)
    end

    local header = {
        type = msgType
    }
    return self:__sendMsg(port, dest, header, body)
end

---Send a message over this interface, and wait for the reply.
---Returns the message, "setup_fail", "sent_fail", or "timeout" after 2 seconds
---@param port number Network port for message (see net.standardPorts)
---@param dest NetAddress|string Destination IP address, HW address, or hostname
---@param msgType string Message type
---@param body table|string|nil Message body
---@param timeout? number Reply timeout in seconds (default is 2 seconds, set to -1 to disable)
---@return NetMessage|string rsp Response message, or error string
function NetInterface:sendSync(port, dest, msgType, body, timeout)
    expect(1, port, 'number')
    expect(2, dest, 'number', 'string')
    expect(3, msgType, 'string')
    expect(4, body, 'table', 'string')
    expect(5, timeout, 'number', 'nil')

    if not net.setup() then
        return "setup_fail"
    end

    if net.isIPV4(dest) then
        dest = net.ipToNumber(dest)
    end

    local head = {
        type = msgType
    }

    local id = self:__sendMsg(port, dest, head, body)
    if id == -1 then
        return "send_fail"
    end

    return self:waitForMessage(port, function(_, message)
        return not (message.dest == self.__ip and message.msgid == id)
    end, timeout)
end

---Send a message over this interface
---@param port number Network port for message (see net.standardPorts)
---@param dest NetAddress|string Destination IP address, HW address, or hostname
---@param header NetMessage.Header Message header, should include type parameter
---@param body table|string|nil Message body
---@return integer msgId Message ID or -1 on error
function NetInterface:sendAdv(port, dest, header, body)
    expect(1, port, 'number')
    expect(2, dest, 'number', 'string')
    expect(3, header, 'table')
    expect(4, body, 'table', 'string')

    if not self:setup() then
        return -1
    end

    if net.isIPV4(dest) then
        dest = net.ipToNumber(dest)
    end

    return self:__sendMsg(port, dest, header, body)
end

---Send a message over this interface, and wait for the reply.
---Returns the message, "setup_fail", "sent_fail", or "timeout" after 2 seconds
---@param port number Network port for message (see net.standardPorts)
---@param dest NetAddress|string Destination IP address, HW address, or hostname
---@param header NetMessage.Header Message header, should include type parameter
---@param body table|string|nil Message body
---@param timeout? number Reply timeout in seconds (default is 2 seconds, set to -1 to disable)
---@return NetMessage|string rsp Response message, or error string
function NetInterface:sendAdvSync(port, dest, header, body, timeout)
    expect(1, port, 'number')
    expect(2, dest, 'number', 'string')
    expect(3, header, 'table')
    expect(4, body, 'table', 'string')
    expect(5, timeout, 'number', 'nil')

    if not net.setup() then
        return "setup_fail"
    end

    if net.isIPV4(dest) then
        dest = net.ipToNumber(dest)
    end

    local id = self:__sendMsg(port, dest, header, body)
    if id == -1 then
        return "send_fail"
    end

    return self:waitForMessage(port, function(_, message)
        return not (message.dest == self.__ip and message.msgid == id)
    end, timeout)
end

---Reply to a message over this network interface
---@param port number Network port for reply (see net.standardPorts)
---@param old NetMessage Message object to reply to
---@param header NetMessage.Header Reply header, should include type parameter
---@param body table|string|nil Reply body
---@return integer msgId Reply id **OR** `-1` on send error
function NetInterface:reply(port, old, header, body)
    expect(1, port, 'number')
    expect(2, old, 'table')
    expect(3, header, 'table')
    expect(4, body, 'table', 'string')

    if not self:setup() then
        return -1
    end

    if old.header.conId then
        header.destConId = old.header.conId
    end
    if old.header.domain then
        header.domain = old.header.domain
    end

    return self:__sendMsg(port, old.origin, header, body, old.msgid)
end

---Ping destination and return time
---@param dest NetAddress|string Destination hostname, IP address, HW address
---@param timeout number? Ping timeout (defaults to `net.DEFAULT_TIMEOUT`)
---@return number time Time to ping response or `-1` on error
---@return string? error
function NetInterface:ping(dest, timeout)
    local sTime = os.epoch('utc') ---@type number
    local iPStr = net.ipFormat(self:resolveHostname(dest))
    local rt = self:sendSync(net.standardPorts.network, dest, 'ping', {}, timeout)
    if type(rt) ~= 'table' then
        self.log:warn('Error pining %s: %s', iPStr, rt)
        return -1, rt --[[@as string]]
    end
    local elapsed = os.epoch('utc') - sTime
    self.log:debug('Received ping return from %s after %ss', iPStr, elapsed / 1000)
    return elapsed
end

---Get the current subnet mask
---@return number? mask
function NetInterface:getSubnetMask()
    return self.__subnetMask
end