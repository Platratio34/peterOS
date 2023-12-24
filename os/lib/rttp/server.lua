local rttp = pos.require("rttp.base")

local isSetup = false

local id = os.getComputerID()
local hostname = ""

local debug = false

local modem = nil

local function debugMsg(msg)
    if debug then
        print(msg)
    end
end

local function setup(side, host) 
    if isSetup then return false end
    -- modem = peripheral.find("modem") or error("No Modem Attached", 0)
    local modems = { peripheral.find("modem", function(name, modem)
        return modem.isWireless()
    end) }
    if #modems == 0 then
        error("No Modem Attached", 0)
        return false
    end
    modem = modems[1]
    modem.open(80)
    hostname = host
    print("Started server on port 80 with hostname " .. hostname)

    id = os.getComputerID()
    isSetup = true
    return true
end

local function getIsSetup()
    return isSetup
end

local function close()
    modem.close(80)
    isSetup = false
end

local function reply(msg, code, body, headers)
    debugMsg("reply sent to "..msg.origin.." code "..code)
    rttp.send(modem, id, msg.origin, "", msg.method, code, body, headers)
end

local function waitForMsg()
    local msg = nil
    debugMsg("waiting for msg")
    repeat
        local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
        if channel == 80 then
            if debug then
                debugMsg("recived msg:")
                for k,v in pairs(message) do
                    debugMsg("  "..k.." = "..tostring(v))
                end
            end
            if message.type then
                if message.type == "rttp" then
                    debugMsg("recived rttp message for "..message.host)
                    if message.host == id then
                        msg = message
                        debugMsg("recive rttp message for server")
                    elseif message.host == hostname and message.method == "FIND" then
                        debugMsg("recive rttp find message")
                        rttp.send(modem, id, message.origin, "", "HOST", 200, hostname, {})
                    end
                end
            end
        end
    until msg
    return msg
end

return {
    setup = setup,
    isSetup = getIsSetup,
    close = close,
    waitForMsg = waitForMsg,
    reply = reply
}