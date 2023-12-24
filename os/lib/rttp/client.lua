local rttp = pos.require("rttp.base")

local isSetup = false

local id = os.getComputerID()

local dnt = {}

local waiting = false

local debug = false

local modem = nil

local function debugMsg(msg)
    if debug then
        print(msg)
    end
end

local function setup(side) 
    if isSetup then return false end
    -- modem = peripheral.find("modem") or error("No Modem Attached", 0)
    local modems = { peripheral.find("modem", function(name, mdm)
        return mdm.isWireless()
    end) }
    if #modems == 0 then
        error("No Modem Attached", 0)
        return false
    end
    modem = modems[1]
    modem.open(80)

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

local function waitForMsg(host)
    local msg = nil
    debugMsg("waiting for msg")
    local sTime = os.time("utc")
    local timeout = os.startTimer(2)
    repeat
        local event = { os.pullEvent() }
        if event[1] == "modem_message" then
            local eName, side, channel, replyChannel, message, distance = unpack(event)
            if channel == 80 then
                if debug then
                    debugMsg("recived msg:")
                    for k,v in pairs(message) do
                        debugMsg("  "..k.." = "..tostring(v))
                    end
                end
                if message.type then
                    if message.type == "rttp" and message.host == id then
                        if message.method == "HOST" then
                            debugMsg("recived rttp host message")
                            dnt[message.body] = message.origin
                            if host then
                                msg = message
                            end
                        else
                            debugMsg("recived rttp message for client")
                            msg = message
                        end
                    end
                end
            end
        elseif event[1] == "timer" and event[2] == timeout then
            waiting = false
            return "timeout"
        end
    until msg
    waiting = false
    return msg
end

local function getDN(domain)
    debugMsg("getting domain id")
    rttp.send(modem, id, domain, "", "FIND", 0, "", {})
    local rsp = waitForMsg(true)
    if(rsp == "timeout") then
        return "timeout"
    end
    return rsp.origin
end

local function reqGet(host, path)
    if not isSetup then return false end
    if waiting then return false end
    if not tonumber(host) then
        if dnt[host] == nil then
            if getDN(host) == "timeout" then
                return "timeout"
            end
        end
        host = dnt[host]
    end
    debugMsg("GET sent to "..host)
    rttp.send(modem, id, host, path, "GET", 0, "", {})
    waiting = true
    return true
end
local function reqGetSync(host, path)
    local req = reqGet(host, path)
    if req == "timeout" then
        return "timeout"
    elseif req == true then
        return waitForMsg()
    end
    return nil
end

local function reqPost(host, path, body)
    if not isSetup then return false end
    if waiting then return false end
    if not tonumber(host) then
        if dnt[host] == nil then
            if getDN(host) == "timeout" then
                return "timeout"
            end
        end
        host = dnt[host]
    end
    debugMsg("POST sent to "..host)
    rttp.send(modem, id, host, path, "POST", 0, body, {})
    waiting = true
    return true
end
local function reqPostSync(host, path, body)
    local req = reqPost(host, path, body)
    if req == "timeout" then
        return "timeout"
    elseif req == true then
        return waitForMsg()
    end
    return nil
end

local function clearDNT()
    dnt = {}
end

return {
    setup = setup,
    isSetup = getIsSetup,
    close = close,
    get = reqGet,
    getSync = reqGetSync,
    post = reqPost,
    postSync = reqPostSync,
    clearDNT = clearDNT,
    waitForMsg = waitForMsg
}