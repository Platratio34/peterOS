local rttp = pos.require("rttp.base")
local rttps = pos.require("rttps.base")
-- local rsa = pos.require("rsa")
local ecc = pos.require("ecc")

local appdata = "/home/.appdata/rttps/"

local privateKey = nil
local publicKey = nil

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
    local modems = { peripheral.find("modem", function(name, modem)
        return modem.isWireless()
    end) }
    if #modems == 0 then
        error("No Modem Attached", 0)
        return false
    end
    modem = modems[1]
    modem.open(80)

    local prKF = fs.open(appdata .. "private.key", "r")
    local pbKF = fs.open(appdata .. "public.key", "r")
    if prKF == nil or pbKF == nil then
        print("Missing key files, generating new ones")
        -- publicKey, privateKey = rsa.keygen.generateKeyPair()
        publicKey, privateKey = ecc.keypair(ecc.random.random());
        prKF = fs.open(appdata .. "private.key", "w")
        pbKF = fs.open(appdata .. "public.key", "w")
        if prKF == nil or pbKF == nil then
            print("Failed to write to key files")
            return false
        end
        pbKF.write(textutils.serialise(publicKey))
        prKF.write(textutils.serialise(privateKey))
    else
        publicKey = textutils.unserialise(pbKF.readAll())
        privateKey = textutils.unserialise(prKF.readAll())
    end
    pbKF.close()
    prKF.close()

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

local function waitForMsgInt(host)
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
                            dnt[message.body] = {
                                id = message.origin,
                            }
                            if message.code == 101 and message.header.upgrade == "rttps" then
                                dnt[message.body].rttps = true
                                dnt[message.body].publicKey = message.header.publicKey
                            end
                            if host then
                                msg = message
                            end
                        else
                            debugMsg("recived rttp message for client")
                            msg = message
                        end
                    elseif message.type == "rttps" and message.host == id then
                        debugMsg("recived rttps message for client")
                        msg = message
                        msg.body = rttps.decode(msg.body, privateKey)
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
local function waitForMsg()
    return waitForMsgInt(false)
end
local function waitForHost()
    return waitForMsgInt(true)
end

local function getDN(domain)
    if dnt[domain] ~= nil then
        return dnt[domain].id
    end
    debugMsg("getting domain id")
    rttp.send(modem, id, domain, "", "FIND", 0, "", {})
    local rsp = waitForHost()
    if rsp == "timeout" then
        return "timeout"
    end
    return rsp.origin
end

local function reqGet(host, path)
    if not isSetup then return false end
    if waiting then return false end
    if tonumber(host) then
        return false
    end
    if dnt[host] == nil then
        if getDN(host) == "timeout" then
            return "timeout"
        end
        if dnt[host] == nil then
            return "unknown_host"
        end
    end
    debugMsg("GET sent to " .. host)
    if dnt[host].rttps then
        local body = { rttpsClientKey = publicKey }
        rttps.send(modem, id, dnt[host].id, path, "GET", 0, rttps.encode(body, dnt[host].publicKey), {})
    else
        rttp.send(modem, id, dnt[host].id, path, "GET", 0, "", {})
    end
    waiting = true
    return true
end
local function reqGetSync(host, path)
    local req = reqGet(host, path)
    if req == "timeout" or req == "unknown_host" then
        return req
    elseif req == true then
        return waitForMsg()
    end
    return nil
end

local function reqPost(host, path, body)
    if not isSetup then return false end
    if waiting then return false end
    if tonumber(host) then
        return false
    end
    if dnt[host] == nil then
        if getDN(host) == "timeout" then
            return "timeout"
        end
        if dnt[host] == nil then
            return "unknown_host"
        end
    end
    debugMsg("POST sent to " .. host)
    if dnt[host].rttps then
        body.rttpsClientKey = publicKey
        rttps.send(modem, id, dnt[host].id, path, "POST", 0, rttps.encode(body, dnt[host].publicKey), {})
    else
        rttp.send(modem, id, dnt[host].id, path, "POST", 0, body, {})
    end
    waiting = true
    return true
end
local function reqPostSync(host, path, body)
    local req = reqPost(host, path, body)
    if req == "timeout" or req == "unknown_host" then
        return req
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
    waitForMsg = waitForMsg,
    waitForHost = waitForHost,
}