---@class NetSocket
---@field id number **Read Only** Socket ID
---@field name string Socket name
---@field connected boolean If the socket is connected to the remote
---@field protected _open boolean If the socket is open (ready to accept incoming and outgoing data)
---@field remote NetAddress Socket end address (IP or hostname)
---@field private __remoteAddr NetAddress IP address of socket end
---@field port number Networking port for socket
---@field onPacketCallback fun(packet: NetSocket.Packet)|nil On packet callback function
---@field private __nextPacketId number ID of next outgoing data packet
---@field private __lastPacket nil|table Last send data packet
---@field private __packetQueueOut Queue Queue of pending outgoing data packets
---@field private __dataQueueIn Queue Incoming packet buffer
---@field private __waiting boolean If the socket is waiting on a confirmation for the last data packet
---@field private __handlerID number Event handler ID
---@field private __lastRemoteId number Last data packet ID from remote
---@field private __timer number Timer ID for confirmation timeout
---@field private __tries number Number of attempts to send last data packet
---@field private __remoteSocketId number|nil **NET LEVEL** NAT ID for socket at remote
---@field TYPE string **STATIC** message type for socket: `socket`
---@field MAX_TRIES number **STATIC** maximum retries to send a packet: `3`
---@field ON_PACKET_EVENT string **STATIC** os event type for on packet: `socket_on_packet`
local NetSocket = {
    __nextPacketId = 0,
    TYPE = "socket",
    MAX_TRIES = 3,
    ON_PACKET_EVENT = "socket_on_packet",
    name = ""
}
local NetSocketMT = {
    __index = NetSocket,
}

local nextId = 0

---Net Socket module
local sockets = {
}
---Net Socket module
net.sockets = sockets

---Instantiate a new network socket
---@param remote NetAddress address of the other end of the socket
---@param port number port for the socket
---@return NetSocket socket
---@nodiscard
local function instantiate(remote, port)
    local o = {}
    setmetatable(o, NetSocketMT)
    o:__init__(remote, port)
    o.id = nextId
    nextId = nextId + 1
    return o
end
sockets.NetSocket = instantiate
sockets.NetSocketType = NetSocket.TYPE ---Message type for net sockets: `socket`

---**Internal** Initialize the socket
---@param remote NetAddress address of the other end of the socket
---@param port number port for the socket
function NetSocket:__init__(remote, port)
    self.remote = remote
    self.port = port or net.standardPorts.network
    self.connected = false
    self.__packetQueueOut = pos.Queue()
    self.__dataQueueIn = pos.Queue()
    self.__tries = 0
    self.__lastRemoteId = -1
end

---Send a data packet through the socket
---@param data any the data to send
function NetSocket:send(data)
    if not self._open then
        error("SocketError: Socket must be open to send data", 2)
    end
    local id = self.__nextPacketId
    self.__nextPacketId = id + 1
    local packet = {
        id = id,
        data = data
    }
    if self.__packetQueueOut:size() == 0 and not self.__waiting then
        self:_sendDataPacket(packet)
    else
        self.__packetQueueOut:enqueue(packet)
    end
end

---**Internal** Send a data packet to the remote, resetting last packet and timer
---@param packet NetSocket.Packet data packet to send
function NetSocket:_sendDataPacket(packet)
    self.__lastPacket = packet
    self:_sendPacket(packet)
    self.__waiting = true
    self.__timer = os.startTimer(5)
    self.__tries = self.__tries + 1
    -- print("set data packet "..packet.id)
end

---**Internal** Send a generic packet to the remote
---@param packet NetSocket.Packet packet to send
function NetSocket:_sendPacket(packet)
    local r = net.sendAdv(self.port, self.__remoteAddr, {
        type = NetSocket.TYPE,
        destSocketId = self.__remoteSocketId
    }, packet)
    if r == -1 then
        error("SocketError: Unable to send packet", 3)
    end
end

---**Internal** Processes an incoming packet
---@param packet NetSocket.Packet packet to process
function NetSocket:_onPacket(packet)
    self.connected = true
    if packet.id == -1 then
        if packet.data == "CLOSE" then
            self:_sendPacket({
                id = -1,
                data = "CLOSE"
            })
            net.unregisterMsgHandler(self.__handlerID)
            self.connected = false
        elseif packet.data == "GOT" then
            os.cancelTimer(self.__timer)
            self.__timer = -1
            self.__tries = 0
            self.__waiting = false
            if self.__packetQueueOut:size() > 0 then
                self:_sendDataPacket(self.__packetQueueOut:dequeue())
            end
        end
        return
    end
    if packet.id ~= self.__lastRemoteId + 1 then -- out of order packet
        -- print("Out of order packet: expected "..(self.__lastRemoteId + 1).."; got "..packet.id)
        return
    end

    self:_sendPacket({
        id = -1,
        data = "GOT"
    })
    self.__lastRemoteId = packet.id
    self.__dataQueueIn:enqueue(packet.data)
    os.queueEvent(NetSocket.ON_PACKET_EVENT, self)
    if self.onPacketCallback then
        self.onPacketCallback(packet)
    end
end

---Open the socket. Must be called before trying to send data.
function NetSocket:open()
    if self._open then
        error("SocketError: Socket already open", 2)
    end
    self.__remoteAddr = net.realizeHostname(self.remote)
    self.__handlerID = pos.addEventHandler(function(event)
        if event[1] == net.NET_MESSAGE_EVENT then
            local msg = event[2]
            ---@cast msg NetSocket.Message
            if msg.port ~= self.port then return end
            if msg.header.type ~= NetSocket.TYPE then return end
            if msg.origin ~= self.__remoteAddr then return end
            if msg.header.originSocketId then
                if self.__remoteSocketId and self.__remoteSocketId ~= msg.header.originSocketId then return end
                self.__remoteSocketId = msg.header.originSocketId
            end
            self:_onPacket(msg.body)
        elseif event[1] == "timer" and event[2] == self.__timer then
            if self.__waiting then
                if self.__tries > NetSocket.MAX_TRIES then
                    self.__waiting = false
                    self:close()
                    error("SocketError: Too many retries for socket, closing", 0)
                    return
                end
                self:_sendDataPacket(self.__lastPacket)
            end
        end
    end, nil, self.name)
    net.open(self.port)
    self._open = true
end

---Closes the socket and sends close message. Data can not be sent after closing.
function NetSocket:close()
    if not self._open then
        error("SocketError: Socket was not open", 2)
    end
    self._open = false
    self:_sendPacket({
        id = -1,
        data = "CLOSE"
    })
end

---Check if the socket has any data waiting to be pulled from it
---@return boolean
function NetSocket:hasData()
    return self.__dataQueueIn:size() > 0
end

---Get the next packet's data if present, else returns nil
---@param time nil|number wait time for next packet, leave nil to not wait
---@return any|nil data next packet from socket or nil if no more packets left
function NetSocket:poll(time)
    if self:hasData() then
        return self.__dataQueueIn:dequeue()
    end
    if time == nil then
        return nil
    end
    local timeout = os.startTimer(time)
    local e = pos.waitForEventCheck(nil, function(event)
        if event[1] == "timer" and event[2] == timeout then
            return true
        elseif event[1] == NetSocket.ON_PACKET_EVENT and event[2].id == self.id then
            return true
        end
        return false
    end)
    if not self:hasData() then
        return nil
    end
    return self.__dataQueueIn:dequeue()
end

---Returns if the socket has been opened
---@return boolean open
function NetSocket:isOpen()
    return self._open
end

---@class NetSocket.Packet
---@field id number packet id, -1 for control messages
---@field data any packet data, action for control message

---@class NetSocket.Message : NetMessage Net message for socket
---@field header NetSocket.Message.Header Header table
---@field body NetSocket.Packet Socket packet

---@class NetSocket.Message.Header : NetMessage.Header
---@field originSocketId nil|number Origin NAT socket ID
---@field destSocketId nil|number Destination NAT socket ID

local namedSockets = {} ---@type table<string, NetSocket> Table of named sockets

---Returns if a socket with name exists
---@param name string socket name
---@return boolean exists
function sockets.socketExists(name)
    return namedSockets[name] ~= nil
end

---Make a new named socket. **CLOSES SOCKET IF ONE EXISTS**
---@param name string socket name
---@param remote NetAddress socket remote address
---@param port number socket port
---@return NetSocket socket
function sockets.makeSocket(name, remote, port)
    if namedSockets[name] then
        if namedSockets[name]:isOpen() then
            namedSockets[name]:close()
        end
    end
    local socket = instantiate(remote, port)
    namedSockets[name] = socket
    socket.name = name
    return socket
end

---Gets named socket, or creates one if not present, returning the socket
---@param name string socket name
---@param remote NetAddress socket remote address
---@param port number socket port
---@return NetSocket socket
function sockets.getOrMakeSocket(name, remote, port)
    if namedSockets[name] then
        return namedSockets[name]
    end
    local socket = instantiate(remote, port)
    namedSockets[name] = socket
    socket.name = name
    return socket
end

---Gets named socket
---@param name string socket name
---@return NetSocket|nil socket
function sockets.getSocket(name)
    return namedSockets[name]
end

---Closes the named socket and removes it
---@param name string socket name
function sockets.closeSocket(name)
    if namedSockets[name] and namedSockets[name]:isOpen() then
        namedSockets[name]:close()
        namedSockets[name] = nil
    end
end

---Get a list of the names of all tracked sockets
---@return string[] socketNames
function sockets.listSockets()
    local names = {}
    for name, _ in pairs(namedSockets) do
        table.insert(names, name)
    end
    return names
end