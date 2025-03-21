
---@class WlanDriver
---@field name string
---@field package _network Wlan.Network?
---@field package _hwAddr string
---@field package _log Logger
---@field package _wrapper WlanDriver.Wrapper
---@field package _known { string: { ['time']: number, ['network']: Wlan.Network } }
---@field package _addresses { NetAddress: boolean }
---@field private __conectingLock Lock?
---@field private __queryLock Lock?
---@field private __querySSID string?
---@field private __modem ModemPeripheral
---@field private __modemName string
---@field private __handlerId integer
local WlanDriver = {}

local WlanDriverMT = {
    __index = WlanDriver
}

local wlanI = 0

---Create a new WLAN driver
---@param name string? Driver name. Must be computer unique. If omitted, with be in the pattern `wlan#`
---@param modem ModemPeripheral? Modem for the driver to use. If not provided, will find a wireless modem or error
---@return WlanDriver driver
function net.WlanDriver(name, modem)
    local o = {}
    setmetatable(o, WlanDriverMT)
    ---@cast o WlanDriver
    if not name then
        name = "wlan"..(wlanI)
    end
    o:__init__(name, modem)
    wlanI = wlanI + 1
    return o
end

---Initialize the wlan driver
---@param name string
---@param modem ModemPeripheral?
---@package
function WlanDriver:__init__(name, modem)
    self.name = name
    self._hwAddr = os.computerId() .. '-' .. name
    self._log = pos.Logger('net/'..name, false, true)
    self._known = {}
    self._addresses = {}
    if modem then
        self.__modem = modem
    else
        self._log:info("No modem provided, finding one")
        local modems = {peripheral.find('modem', function(n, t)
            ---@cast t ModemPeripheral
            return t.isWireless()
        end) } ---@cast modems ModemPeripheral[]
        if #modems < 1 then
            self._log:fatal("No wireless modem attached")
            error('No wireless modem attached', 3)
        end
        self.__modem = modems[1]
    end
    self.__modemName = peripheral.getName(self.__modem)
    self.__modem.open(20000)
    self.__handlerId = pos.addEventHandler(function(event)
        local eventName = event[1]
        if eventName == 'modem_message' then
            self:__onMdmMsg(event)
        end
    end, nil, self.name..'-driver')
end

---Event handler for modem message event
---@param event ModemMessageEvent
---@private
function WlanDriver:__onMdmMsg(event)
    local _, side, ch, _, msg = table.unpack(event)
    if side ~= self.__modemName then
        return
    end
    if not self._network then
        -- listen for advertisements only
        if ch ~= 20000 then
            return
        end
        ---@cast msg Wlan.AdvertMessage
        
        if self.__queryLock then -- we are currently trying to find a network
            if msg.method == 'query' and msg.dest == self._hwAddr and msg.ssid == self.__querySSID then
                ---@cast msg Wlan.QueryReturnMessage
                self.__queryLock:release(msg.body)
            end
        end
        if msg.method == 'advert' then
            self._known[msg.ssid] = {
                time = os.clock(),
                network = msg.body
            }
        end
        return
    end
    if ch ~= self._network.channel then
        return
    end
    ---@cast msg Wlan.Message
    if msg.ssid ~= self._network.ssid then
        return
    end
    if msg.dest ~= self._hwAddr then
        return
    end
    if msg.method == 'connect' then
        local body = msg.body --[[@as Wlan.ConnectReturnBody]]
        if body.valid then
            self.__conectingLock:release()
            self.__conectingLock = nil
        else -- something went wrong connecting
            self.__conectingLock:release(body.reason)
            self.__conectingLock = nil
            self._network = nil
        end
        return
    end
    if msg.sig then
        -- message had encrypted body
        local s, body = net.encrypt.decrypt(msg.body --[[@as number[] ]], msg.sig, self._network.publicKey)
        if not s then
            --TODO: Throw error to log
            return
        end
        msg.body = body
    else
        -- ??
    end

    if msg.method == 'msg' then
        os.queueEvent('modem_message', self.name, msg.body[1], msg.body[1], msg.body[2], nil)
    end
end

---Get a list of the currently known networks available
---@return string[] networks SSIDs of known networks
---@see WlanDriver.getNetworkDetails to get the details on the networks
function WlanDriver:getKnown()
    local networks = {}
    local cTime = os.clock()
    for ssid, net in pairs(self._known) do
        if cTime - net.time > 120 then
            self._known[ssid] = nil
        else
            table.insert(networks, ssid)
        end
    end
    return networks
end

---Connect to the specified network. Function will block until connection is established or failed
---@param ssid string SSID of the network to connect to
---@param key string? Authentication key, if required
---@return boolean connected
---@return string? message
function WlanDriver:connect(ssid, key)
    self:disconnect()
    self.__conectingLock = pos.Lock():lock()

    local network
    if self._known[ssid] then
        network = self._known[ssid]
    else
        -- try to find the network
        self.__queryLock = pos.Lock():lock()
        self.__querySSID = ssid
        self.__modem.transmit(20000, 20000, {
            method = 'query',
            ssid = ssid,
            body = {
                publicKey = net.encrypt.getPublicKey()
            }
        })

        local s, m = self.__queryLock:await(5)
        if not s then
            return false, 'query-timeout'
        end
        ---@cast m Wlan.Network
        network = m
        self._known[m.ssid] = {
            time = os.clock(),
            network = m
        }
    end

    if network.authMode == 'key' and not key then
        return false, 'auth-key-requiered'
    end
    
    self:__connectInt(network, key)
    local s, m = self.__conectingLock:await(5)
    if not s then
        return false, 'auth-timeout'
    elseif m then
        return false, m
    end

    -- TODO: probably need to get IP here
    
    return true
end

---Disconect the drive for the current network
---@return boolean wasConnected If the driver was connected to a network
function WlanDriver:disconnect()
    if not self._network then
        return false
    end
    self:_sendMsg('disconnect', self._hwAddr)
    self.__modem.close(self._network.channel)
    self._network = nil
    return true
end

---Checks if the driver is currently connected to a network and able to send messages.
---@return boolean connected
function WlanDriver:isConnected()
    return self._network ~= nil and self.__conectingLock == nil
end

---Gets the network the driver is currently connected to. Will return non-nil if the driver is currently connecting to a network, but unable to send messages.
---@return string|nil network The SSID of the connected network
---@see WlanDriver.isConnected to check if messages can be sent
function WlanDriver:getNetwork()
    if not self._network then
        return nil
    end
    return self._network.ssid
end

---Get the details of a known network by ssid
---@param ssid string Network SSID to get details of
---@return Wlan.Network? network The network, or `nil` if the network is not known
---@see WlanDriver.getKnown to get a list of known networks by SSID
function WlanDriver:getNetworkDetails(ssid)
    if self._network and self._network.ssid == ssid then
        return self._network
    end
    local n = self._known[ssid]
    if not n then
        return nil
    end
    local network = n.network
    return network
end

---@private
---@param network Wlan.Network
---@param key string?
function WlanDriver:__connectInt(network, key)
    self._network = network
    self.__modem.open(network.channel)
    local authKey = nil
    if key then
        authKey = net.encrypt.encrypt(key, network.publicKey)
    end
    local msg = { ---@type Wlan.ConnectBody
        authKey = authKey,
        publicKey = net.encrypt.getPublicKey()
    }
    self:_sendMsg('connect', msg)
end

---@param method Wlan.Message.Method
---@param body table|string
---@private
function WlanDriver:_sendMsg(method, body)
    local network = self._network
    if network == nil then
        error('Not connected to a network', 3)
    end
    local msg = { ---@type Wlan.Message
        ssid = network.ssid,
        method = method,
        origin = self._hwAddr,
        body = body
    }
    if not self.__conectingLock then
        -- encrypt the body
        local ser = textutils.serialise(body)
        local enc, sig = net.encrypt.encrypt(ser, network.publicKey)
        msg.body = enc
        msg.sig = sig
    end
    self.__modem.transmit(network.channel, network.channel, msg)
end

---Register an IP with this driver on the current network
---@param addr NetAddress Address to register
function WlanDriver:addAddress(addr)
    if not self._network then
        error("Driver not connect to a network", 2)
    end
    local msg = { ---@type Wlan.RegisterIPBody
        addr = addr
    }
    self._addresses[addr] = true
    self:_sendMsg('register-ip', msg)
end

---Un-Register an IP with for driver on the current network
---@param addr NetAddress Address to remove
function WlanDriver:removeAddress(addr)
    if not self._network then
        error("Driver not connect to a network", 2)
    end
    local msg = { ---@type Wlan.RegisterIPBody
        addr = addr,
        remove = true
    }
    self._addresses[addr] = nil
    self:_sendMsg('register-ip', msg)
end

---Sets if the driver will get broadcast messages 
---@param broadcast boolean If the driver should receive broadcast messages
function WlanDriver:receiveBroadcast(broadcast)
    if not self._network then
        error("Driver not connect to a network", 2)
    end
    local msg = { ---@type Wlan.RegisterIPBody
        broadcast = broadcast
    }
    self:_sendMsg('register-ip', msg)
end

---Send a message over the current network
---@param port integer Port to send the message on
---@param message NetMessage Message to send
function WlanDriver:send(port, message)
    if not self._network then
        error('WLAN Driver not connected to a network', 2)
    end
    self:_sendMsg('msg', {port, message})
end

---Get a modem wrapper for creating a network interface
---@return WlanDriver.Wrapper wrapper
function WlanDriver:getModemWrapper()
    if self._wrapper then
        return self._wrapper
    end
    local wrapper = { ---@type WlanDriver.Wrapper
        transmit = function(port, _, msg)
            ---@cast msg NetMessage
            if not self._addresses[msg.origin] then -- automaticlly register any new address we are sending from
                self:addAddress(msg.origin)
            end
            self:send(port, msg)
        end,
        isWireless = function() return true end,
        open = function(port)
            -- do we actaully need this?
        end,
        isOpen = function(port)
            return true
        end,
        close = function(port)
            -- do we actaully need this?
        end,
        closeAll = function()
            -- do we actaully need this?
        end
    }
    setmetatable(wrapper, {
        __name = 'peripheral',
        types = {
            ['wlan_driver'] = 'wlan_driver'
        },
        name = self.name
    })
    self._wrapper = wrapper
    return wrapper
end

---Dispose of the driver.
---
---**DRIVER AND WRAPPER WILL NOT WORK AFTER CALLING THIS**
function WlanDriver:dispose()
    self:disconnect()
    pos.removeEventHandler(self.__handlerId)
end