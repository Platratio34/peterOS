
---@class WlanDriver
---@field name string
---@field _network Wlan.Network?
---@field __known { string: { ['time']: number, ['network']: Wlan.Network } }
---@field __modem ModemPeripheral
---@field __modemName string
---@field __handlerId integer
---@field _hwAddr string
---@field _connecting boolean?
local WlanDriver = {}

local WlanDriverMT = {
    __index = WlanDriver
}

local wlanI = 0
function WlanDriver.new(name, modem)
    local o = {}
    setmetatable(o, WlanDriverMT)
    if not name then
        name = "wlan"..(wlanI)
    end
    o:__init__(name, modem)
    wlanI = wlanI + 1
    return o
end

function WlanDriver:__init__(name, modem)
    self.name = name
    self._hwAddr = os.computerId() .. '-' .. name
    if modem then
        self.__modem = modem
    else
        self.__modem = peripheral.find('modem', function(n, t)
            ---@cast t ModemPeripheral
            return t.isWireless()
        end)
        if not self.__modem then
            error('No wireless modem attached', 3)
        end
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

---@param event ModemMessageEvent
function WlanDriver:__onMdmMsg(event)
    local _, side, ch, _, msg = table.unpack(event)
    if side ~= self.__modemName then
        return
    end
    if not self._network then
        -- listen for advertisments only
        if ch ~= 20000 then
            return
        end
        ---@cast msg Wlan.Message
        if msg.method == 'advert' then
            self.__known[msg.ssid] = {
                time = os.clock(),
                network = msg.msg --[[@as Wlan.Network]]
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
        -- confirmed connected
        self._connecting = nil
        return
    end
    if msg.sig then
        -- message had encrypted body
        local s, body = net.encrypt.decrypt(msg.msg --[[@as number[] ]], msg.sig, self._network.publicKey)
        if not s then
            --TODO: Throw error to log
            return
        end
        msg.sig = nil
        msg.msg = body
    end
end

---Get a list of the currently known networks avalible
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

function WlanDriver:connect(ssid, key)
    if self.__known[ssid] then
        local network = self.__known[ssid]
    end
end

function WlanDriver:_connectInt(network, key)
    if self._network then
        -- disconnect from previous network
        self:_sendMsg('disconnect', self._hwAddr)
        self.__modem.close(self._network.channel)
        self._network = nil
    end
    self._connecting = true

    self._network = network.network
    self:_sendMsg('connect', {
        hwAddr = self._hwAddr,
        authKey = key,
        publicKey = net.encrypt.getPublicKey()
    })
end

---@param method Wlan.Message.Method
---@param msg table|string
function WlanDriver:_sendMsg(method, msg)
    local network = self._network
    if network == nil then
        error('Not connected to a network', 3)
    end
    local body = {
        ssid = network.ssid,
        method = method,
        msg = msg
    } ---@type Wlan.Message
    if not self._connecting then
        -- encrypt the body
        local ser = textutils.serialise(msg)
        local enc, sig = net.encrypt.encrypt(ser, network.publicKey)
        body.msg = enc
        body.sig = sig
    end
    self.__modem.transmit(network.channel, network.channel, body)
end