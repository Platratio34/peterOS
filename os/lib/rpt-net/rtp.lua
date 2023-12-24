---@diagnostic disable
local str = require(".os.lib.strings")

local modem
local isSetup
local hostName

local msgs = {}

local function setup(host)
    if isSetup then return false end
    modem = peripheral.find("modem") or error("No Modem Attached", 0)
    modem.open(4040)   
    
    hostName = host
    isSetup = true
    broadcast("IDENT", hostName)
    return true
end

local function cleanup()
    broadcast("LEAVE", hostName)
    modem.close(4040)
    isSetup = false
end

local function send(dest, method, msg)
    if not isSetup then return false end
    modem.transmit(4040, 4040, dest..":"..hostName..":"..method..":"..msg)
    return true
end

local function broadcast(method, msg)
    if not isSetup then return false end
    modem.transmit(4040, 4040, ":"..hostName..":"..method..":"..msg)
    return true
end

local function hasMessages()
    return #msgs > 0
end

--function getMessage()
--    if not hasMessages() then return nil end
--    local msg = msgs[1]
--    if #msgs > 1 then 
--        for i=2,#msgs do
--            msgs[i-1] = msgs[i]
--        end
--        msgs[#msgs] = nil
--    else
--        msgs[1] = nil
--    end
--    return msg
--end

local function recive()
    while true do
        local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
        if channel == 4040 then
            local dta = str.split(message, ":")
            if #dta > 3 then
                local ot = {
                    dst = dta[1],
                    org = dta[2],
                    mth = dta[3],
                    msg = ""
                }
                for i=4,#dta do
                    if i>4 then ot.msg = ot.mgs..":" end
                    ot.msg = ot.msg..dta[i]
                end
                if ot.dst == "" then
                    ot.brd = true
                end
                if ot.brd or ot.dst == hostName then
                    return ot
                end
            end
        end
    end    
end

return {setup = setup, cleanup = cleanup, send = send, broadcast = broadcast, hasMsg = hasMessages, recive = recive}
