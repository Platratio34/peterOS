
---@class WlanDriver
---@field name string
---@field _network Wlan.Network?
---@field __known { string: { ['time']: number, ['network']: Wlan.Network } }
---@field __modem ModemPeripheral
---@field __modemName string
---@field __handlerId integer
---@field _hwAddr string
---@field _connecting Lock?
---@field _queryLock Lock?
---@field _querySSID string?
---@field _log Logger
local WlanDriver = {}

local WlanDriverMT = {
    __index = WlanDriver
}

local wlanI = 0

---Create a new WLAN driver
---@param name string Driver name. Must be computer unique
---@param modem ModemPeripheral? Modem for the driver to use. If not provided, will find a wireless modem or error
---@return WlanDriver driver
function WlanDriver.new(name, modem)
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
        
        if self._queryLock then -- we are currently trying to find a network
            if msg.method == 'query' and msg.dest == self._hwAddr and msg.ssid == self._querySSID then
                ---@cast msg Wlan.QueryReturnMessage
                self._queryLock:release(msg.body)
            end
        end
        if msg.method == 'advert' then
            self.__known[msg.ssid] = {
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
            self._connecting:release()
            self._connecting = nil
        else -- something went wrong connecting
            self._connecting:release(body.reason)
            self._connecting = nil
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
        msg.sig = nil
        msg.body = body
    end
end

---Get a list of the currently known networks available
---@return string[]
function WlanDriver:getKnown()
    local networks = {}
    local cTime = os.clock()
    for ssid, net in pairs(self.__known) do
        if cTime - net.time > 120 then
            self.__known[ssid] = nil
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
    if self._network then
        -- disconnect from previous network
        self:_sendMsg('disconnect', self._hwAddr)
        self.__modem.close(self._network.channel)
        self._network = nil
    end
    self._connecting = pos.Lock():lock()

    local network
    if self.__known[ssid] then
        network = self.__known[ssid]
    else
        -- try to find the network
        self._queryLock = pos.Lock():lock()
        self._querySSID = ssid
        self.__modem.transmit(20000, 20000, {
            method = 'query',
            ssid = ssid,
            body = {
                publicKey = net.encrypt.getPublicKey()
            }
        })

        local s, m = self._queryLock:await(5)
        if not s then
            return false, 'query-timeout'
        end
        ---@cast m Wlan.Network
        network = m
        self.__known[m.ssid] = {
            time = os.clock(),
            network = m
        }
    end

    if network.authMode == 'key' and not key then
        return false, 'auth-key-requiered'
    end
    
    self:__connectInt(network, key)
    local s, m = self._connecting:await(5)
    if not s then
        return false, 'auth-timeout'
    elseif m then
        return false, m
    end

    -- TODO: probably need to get IP here
    
    return true
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
    if not self._connecting then
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
function WlanDriver:_addAddress(addr)
    if not self._network then
        error("Driver not connect to a network", 2)
    end
    local msg = { ---@type Wlan.RegisterIPBody
        addr = addr
    }
    self:_sendMsg('register-ip', msg)
end

---Un-Register an IP with for driver on the current network
---@param addr NetAddress Address to remove
function WlanDriver:_removeAddress(addr)
    if not self._network then
        error("Driver not connect to a network", 2)
    end
    local msg = { ---@type Wlan.RegisterIPBody
        addr = addr,
        remove = true
    }
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