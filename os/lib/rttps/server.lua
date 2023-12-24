local rttp = pos.require("rttp.base")
local rttps = pos.require("rttps.base")
local rsa = pos.require("rsa")

local appdata = "/home/.appdata/rttps/"

local privateKey = nil
local publicKey = nil

local isSetup = false;
local function getIsSetup() return isSetup end

local id = -1
local hostname = ""

local debug = false

local modem = nil

local function debugMsg(msg)
    if debug then
        print(msg)
    end
end

local function setup(host)
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
    
    local prKF = fs.open(appdata .. "private.key", "r")
    local pbKF = fs.open(appdata .. "public.key", "r")
    if prKF == nil or pbKF == nil then
        print("Missing key files, generating new ones")
        publicKey, privateKey = rsa.keygen.generateKeyPair()
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
    
    isSetup = true
    return true
end

local function close()
    modem.close(80)
    isSetup = false
end

local function reply(msg, code, body, headers)
    debugMsg("reply sent to " .. msg.origin .. " code " .. code)
    if msg.method == "FIND" then msg.method = "HOST" end
    rttps.send(modem, id, msg.origin, "", msg.method, code, rttps.encrypt(body), headers)
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
                if message.type == "rttps" then
                    debugMsg("recived rttp message for "..message.host)
                    if message.host == id then
                        msg = message
                        debugMsg("recive rttps message for server")
                    end
                elseif message.type == "rttp" then
                    if message.host == id then
                        debugMsg("recive rttp message")
                        rttp.send(modem, id, message.origin, "", message.method, 101, "", { upgrade = "rttps", publicKey = publicKey })
                    elseif message.host == hostname and message.method == "FIND" then
                        debugMsg("recive rttp find message")
                        rttp.send(modem, id, message.origin, "", "HOST", 101, hostname, { upgrade = "rttps", publicKey = publicKey })
                    end
                end
            end
        end
    until msg
    msg.body = rttps.decrypt(msg.body)
    return msg
end

return {
    setup = setup,
    isSetup = getIsSetup,
    close = close,
    reply = reply,
    waitForMsg = waitForMsg,
}