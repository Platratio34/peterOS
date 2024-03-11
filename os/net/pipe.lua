---@class NetPipe
---@field name string Pipe name
---@field connected boolean If the pipe is connected to the remote
---@field protected _open boolean If the pipe is open (ready to accept incoming and outgoing data)
---@field remote NetAddress Pipe end address (IP or hostname)
---@field private __remoteAddr NetAddress IP address of pipe end
---@field port number Networking port for pipe
---@field private __nextPacketId number ID of next outgoing data packet
---@field private __lastPacket nil|table Last send data packet
---@field private __packetQueueOut Queue Queue of pending outgoing data packets
---@field private __dataQueueIn Queue Incoming packet buffer
---@field private __waiting boolean If the pipe is waiting on a confirmation for the last data packet
---@field private __handlerID number Event handler ID
---@field private __lastRemoteId number Last data packet ID from remote
---@field private __timer number Timer ID for confirmation timeout
---@field private __tries number Number of attempts to send last data packet
---@field private __remotePipeId number|nil **NET LEVEL** NAT ID for pipe at remote
---@field TYPE string **STATIC** message type for pipe: `pipe`
---@field MAX_TRIES number **STATIC** maximum retries to send a packet: `3`
---@field ON_PACKET_EVENT string **STATIC** os event type for on packet: `pipe_on_packet`
local NetPipe = {
    __nextPacketId = 0,
    TYPE = "pipe",
    MAX_TRIES = 3,
    ON_PACKET_EVENT = "pipe_on_packet",
    name = ""
}
local PipeMT = {
    __index = NetPipe,
}

---Net Pipe module
local pipes = {
}
---Net Pipe module
net.pipes = pipes

---Instantiate a new network pipe
---@param remote NetAddress address of the other end of the pipe
---@param port number port for the pipe
---@return NetPipe pipe
---@nodiscard
local function instantiate(remote, port)
    local o = {}
    setmetatable(o, PipeMT)
    o:__init__(remote, port)
    return o
end
pipes.NetPipe = instantiate
pipes.NetPipeType = NetPipe.TYPE ---Message type for net pipes: `pipe`

---**Internal** Initialize the pipe
---@param remote NetAddress address of the other end of the pipe
---@param port number port for the pipe
function NetPipe:__init__(remote, port)
    self.remote = remote
    self.port = port or net.standardPorts.network
    self.connected = false
    self.__packetQueueOut = pos.Queue()
    self.__dataQueueIn = pos.Queue()
    self.__tries = 0
    self.__lastRemoteId = -1
end

---Send a data packet through the pipe
---@param data any the data to send
function NetPipe:send(data)
    if not self._open then
        error("PipeError: Pipe must be open to send data", 2)
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
---@param packet NetPipe.Packet data packet to send
function NetPipe:_sendDataPacket(packet)
    self.__lastPacket = packet
    self:_sendPacket(packet)
    self.__timer = os.startTimer(5)
    self.__tries = self.__tries + 1
end

---**Internal** Send a generic packet to the remote
---@param packet NetPipe.Packet packet to send
function NetPipe:_sendPacket(packet)
    local r = net.sendAdv(self.port, self.__remoteAddr, {
        type = NetPipe.TYPE,
        destPipeId = self.__remotePipeId
    }, packet)
    if r == -1 then
        error("PipeError: Unable to send packet", 3)
    end
end

---**Internal** Processes an incoming packet
---@param packet NetPipe.Packet packet to process
function NetPipe:_onPacket(packet)
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
            self.__waiting = false
            if self.__packetQueueOut:size() > 0 then
                self:_sendDataPacket(self.__packetQueueOut:dequeue())
            end
            self.__tries = 0
        end
        return
    end
    if packet.id ~= self.self.__lastRemoteId + 1 then -- out of order packet
        print("Out of order packet")
        return
    end

    self:_sendPacket({
        id = -1,
        data = "GOT"
    })
    self.__lastRemoteId = packet.id
    self.__dataQueueIn:enqueue(packet.data)
    os.queueEvent(NetPipe.ON_PACKET_EVENT, self)
end

---Open the pipe. Must be called before trying to send data.
function NetPipe:open()
    if self._open then
        error("PipeError: Pipe already open", 2)
    end
    self.__remoteAddr = net.realizeHostname(self.remote)
    self.__handlerID = pos.addEventHandler(function(event)
        if event[1] == "net_message" then
            local msg = event[2]
            ---@cast msg NetPipe.Message
            -- print('port: '..msg.port ..'?='.. self.port)
            if msg.port ~= self.port then return end
            -- print('type: '..msg.type ..'?='.. NetPipe.TYPE)
            if msg.header.type ~= NetPipe.TYPE then return end
            -- print('origin: '..msg.origin ..'?='.. self.__remoteAddr)
            if msg.origin ~= self.__remoteAddr then return end
            if msg.header.originPipeId then
                if self.__remotePipeId and self.__remotePipeId ~= msg.header.originPipeId then return end
                self.__remotePipeId = msg.header.originPipeId
            end
            self:_onPacket(msg.body)
        elseif event[1] == "timer" and event[2] == self.__timer then
            if self.__tries > NetPipe.MAX_TRIES then
                self:close()
                error("PipeError: Too many retries for pipe, closing", 0)
                return
            end
            self:_sendDataPacket(self.__lastPacket)
        end
    end)
    net.open(self.port)
    self._open = true
end

---Closes the pipe and sends close message. Data can not be sent after closing.
function NetPipe:close()
    if not self._open then
        error("PipeError: Pipe was not open", 2)
    end
    self._open = false
    self:_sendPacket({
        id = -1,
        data = "CLOSE"
    })
end

---Check if the pipe has any data waiting to be pulled from it
---@return boolean
function NetPipe:hasData()
    return self.__dataQueueIn:size() > 0
end

---Get the next packet's data if present, else returns nil
---@param time nil|number wait time for next packet, leave nil to not wait
---@return any|nil data next packet from pipe or nil if no more packets left
function NetPipe:poll(time)
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
        end
        if event[1] == NetPipe.ON_PACKET_EVENT and event[2] == self then
            return true
        end
        return false
    end)
    if not self:hasData() then
        return nil
    end
    return self.__dataQueueIn:dequeue()
end

---Returns if the pipe has been opened
---@return boolean open
function NetPipe:isOpen()
    return self._open
end

---@class NetPipe.Packet
---@field id number packet id, -1 for control messages
---@field data any packet data, action for control message

---@class NetPipe.Message : NetMessage
---@field header NetPipe.Header Header table
---@field body NetPipe.Packet Pipe packet

---@class NetPipe.Header : NetMessage.Header
---@field originPipeId nil|number Origin NAT pipe ID
---@field destPipeId nil|number Destination NAT pipe ID

local namedPipes = {} ---@type table<string, NetPipe> Table of named pipes

---Returns if a pipe with name exists
---@param name string pipe name
---@return boolean exists
function pipes.pipeExists(name)
    return namedPipes[name] ~= nil
end

---Make a new named pipe. **CLOSES PIPE IF ONE EXISTS**
---@param name string pipe name
---@param remote NetAddress pipe remote address
---@param port number pipe port
---@return NetPipe pipe
function pipes.makePipe(name, remote, port)
    if namedPipes[name] then
        if namedPipes[name]:isOpen() then
            namedPipes[name]:close()
        end
    end
    local pipe = instantiate(remote, port)
    namedPipes[name] = pipe
    pipe.name = name
    return pipe
end

---Gets named pipe, or creates one if not present, returning the pipe
---@param name string pipe name
---@param remote NetAddress pipe remote address
---@param port number pipe port
---@return NetPipe pipe
function pipes.getOrMakePipe(name, remote, port)
    if namedPipes[name] then
        return namedPipes[name]
    end
    local pipe = instantiate(remote, port)
    namedPipes[name] = pipe
    pipe.name = name
    return pipe
end

---Gets named pipe
---@param name string pipe name
---@return NetPipe|nil pipe
function pipes.getPipe(name)
    return namedPipes[name]
end

---Closes the named pipe and removes it
---@param name string pipe name
function pipes.closePipe(name)
    if namedPipes[name] and namedPipes[name]:isOpen() then
        namedPipes[name]:close()
        namedPipes[name] = nil
    end
end