pos.require("net.rttp")
-- local Logger = pos.require('logger')
local log = pos.Logger('/home/.pgmLog/nat.log', false)
log:setLevel(pos.LoggerLevel.WARN)
log.logTime = true
_G.net.nat = {
    log = log
}

local cfg = {
    inside = {
        side = "right", -- Side of the computer with the internal modem
        mask = 0xffff0000, -- 255.255.0.0
        baseAddr = 0xC0A80000, -- Private range 192.168.0.0/16
        addr = 0xC0A80001, -- 192.168.0.1
    },
    outside = {
        side = "left", -- Side of the computer with the external modem
    },
    domain = nil, -- Domain name of the NAT, for external routing to NAT web interface
}
local cfgPath = "/home/nat.cfg"
local config = pos.Config(cfgPath, cfg, true)
if not config.loaded then
    error('Unable to load config at '..cfgPath)
    return
end
cfg = config.data
log:info("Config Loaded")

cfg.inside.modem = net.getModem(cfg.inside.side)
cfg.outside.modem = net.getModem(cfg.outside.side)

if cfg.inside.modem == nil or cfg.outside.modem == nil then
    if cfg.inside.modem == nil then log:fatal("Inside modem not found on '"..cfg.inside.side.."'") end
    if cfg.outside.modem == nil then log:fatal("Outside modem not found on '"..cfg.outside.side.."'") end
    error("Modems not attached",0)
    return
end
for _,p in pairs(net.standardPorts) do
    cfg.inside.modem.open(p)
    cfg.outside.modem.open(p)
end

if not net.setup(cfg.outside.modem) then
    error("Network module not setup")
    return
end

local forwarding = {}
local forwardingPath = "/home/nat/forwarding.json"
local forwardHostname = {}
if fs.exists(forwardingPath) then
    local f = fs.open(forwardingPath, "r")
    if f == nil then
        error("Unable to open lease file")
        return
    end
    forwarding = textutils.unserialiseJSON(f.readAll())
    log:info(("%i forwarding rules loaded"):format(#forwarding))
    f.close()
    for name,rule in pairs(forwarding) do
        if rule.hostname then
            cfg.inside.modem:sendMsgAdv2(net.standardPorts.network, cfg.inside.addr, -1, { type = 'net.dns.get' }, { domain = rule.hostname }, net.useMsgId())
            if not forwardHostname[rule.hostname] then
                forwardHostname[rule.hostname] = {}
            end
            table.insert(forwardHostname[rule.hostname], name)
        elseif type(rule.dest) == 'string' then
            rule.dest = net.ipToNumber(rule.dest)
        end
    end
end

local messages = {}
local connectionIds = {}

local function check(side, port, msg)
    ---@cast msg NetAddress
    if port < 10000 or port >= 20000 then return true end
    if type(msg.dest) ~= "number" and type(msg.dest) ~= "string" then
        log:error("Destination type error: type="..type(msg.dest)..": '" .. tostring(msg.dest) .. "'")
        return true
    end
    if side == cfg.inside.side then
        if type(msg.dest) == "string" then -- For the HW address of the NAT
            return msg.dest ~= net.getHWAddr()
        end
        if msg.dest == cfg.inside.addr then -- or IP address for the NAT
            return false
        end

        if msg.dest < 0x0 or msg.dest > 0xffffffff then -- inside valid ip range (0.0.0.0 - 255.255.255.255)
            return true
        end
        if msg.dest >= 0xa9fe0000 and msg.dest <= 0xa9feffff then -- not link local
            return true
        end
        if msg.dest >= 0xe0000000 and msg.dest <= 0xef000000 then -- not multicast
            return true
        end

        if msg.dest >= cfg.inside.baseAddr and msg.dest <= cfg.inside.baseAddr + (0xffffffff - cfg.inside.mask) then -- not local network
            return true
        end
        return false
    elseif side == cfg.outside.side then
        if type(msg.dest) == "string" then
            return msg.dest ~= net.getHWAddr()
        end
        if msg.dest == net.getIP() then
            return false
        end
    end
    return true
end

local function waitForMsg()
    local cont = true
    while cont do
        local event = { os.pullEvent() }
        if event[1] == "modem_message" then
            local _, side, port, _, message, _ = unpack(event)
            cont = check(side, port, message)
            if not cont then
                ---@cast message NetMessage
                return side, port, message
            end
        end
    end
end


local cont = true
net.ignoreMsgOnDecryptFail = false
-- while cont do
--     local side, port, msg = waitForMsg()
local function handlerFunc(side, port, msg)
    if side == cfg.inside.side then
        if msg.dest == cfg.inside.addr then
            if msg.header.type == "rttp" then
                ---@cast msg RttpMessage
                -- rttp.reply(msg, rttp.responseCodes.okay, "text/plain", "NAT Internal Page")
                cfg.inside.modem:sendMsgAdv(net.standardPorts.rttp, msg.origin,
                    {
                        type = "rttp",
                        method = msg.header.method,
                        contentType = "text/plain",
                        code = rttp.responseCodes.okay,
                        rspDomain = msg.header.domain,
                    },
                    "NAT Internal Page",
                    msg.msgid
                )
                log:info("Internal RTTP message for NAT: " .. rttp.stringMessage(msg))
            elseif msg.header.type == 'net.dns.get.return' then
                local record = msg.body ---@cast record DNSRecord
                local hn = msg.header.hostname
                for _, fn in pairs(forwardHostname[hn]) do
                    forwarding[fn].dest = record.ip
                end
            else
                log:info("Internal message for NAT: " .. net.stringMessage(msg))
            end
        else
            -- if msg.header.publicKey then msg.body.publicKey = msg.header.publicKey end
            
            local origin = msg.origin
            if msg.header.conId then
                origin = origin .. msg.header.conId
            end
            local conId = 0
            if connectionIds[origin] then
                conId = connectionIds[origin]
            else
                conId = os.epoch('utc')
                while connectionIds[conId] do
                    conId = conId - 1
                end
            end
            local record = {
                origin = msg.origin,
                msgid = msg.msgid,
                conId = msg.header.conId
            }
            ---@cast msg NetMessage
            msg.header.conId = conId
            if msg.header.publicKey then
                log:debug('Passed message out with public key')
                if net.encrypt.keyMatch(net.encrypt.getPublicKey(), msg.header.publicKey) then
                    log:warn('- Has NAT\'s public key')
                end
                if msg.header.encrypted and msg.body.cipher then
                    log:debug('- Message was encrypted')
                elseif msg.header.encrypted then
                    log:warn('- Message marked as encrypted, but already decrypted')
                end
            end
            cfg.outside.modem:sendMsgAdv2(port, net.getIP(), msg.dest, msg.header, msg.body, msg.msgid)
            log:info(("Out: %s for %s: #%s:%s"):format(net.ipFormat(msg.origin), net.ipFormat(msg.dest),
                tostring(msg.msgid), tostring(msg.header.conId)))
            if messages[conId] == nil then
                messages[conId] = {}
            end
            messages[conId][msg.msgid] = record
        end
    elseif side == cfg.outside.side then
        local conId = msg.header.destConId
        log:debug(('MSG: %s for %s: #%s:%s'):format(net.ipFormat(msg.origin), net.ipFormat(msg.dest), tostring(msg.msgid),
            tostring(conId)))
        if not (messages[conId] and messages[conId][msg.msgid]) then            -- if the message is NOT a response to an outgoing message
            if msg.header.domain == nil or msg.header.domain == cfg.domain then -- if the message is for the NAT itself
                log:info("External message for NAT: " .. net.stringMessage(msg))
                return
            end

            local forward = nil
            for _, rule in pairs(forwarding) do -- check all forwarding rules and find the first one that applies
                if msg.port == rule.port or rule.port == -1 then
                    if msg.header.domain == rule.domain or rule.domain == "*" then
                        forward = rule
                        break
                    end
                end
            end
            if forward ~= nil then -- if there is a forwarding rule for the path
                msg.header.conId = conId
                if msg.header.publicKey then
                    log:debug('Passed message in with public key')
                    if msg.header.encrypted and msg.body.cipher then
                        log:debug('- Message was encrypted')
                    elseif msg.header.encrypted then
                        log:warn('- Message marked as encrypted, but already decrypted')
                    end
                end
                cfg.inside.modem:sendMsgAdv2(port, msg.origin, forward.dest, msg.header, msg.body, msg.msgid)
                -- log:info(("Forwarded message based on rule; %s"):format(net.stringMessage(msg)))
                log:info(("Forwarded message based on rule to %s"):format(net.ipFormat(forward.dest)))
                log:info(("In:  %s for %s: #%s:%s"):format(net.ipFormat(msg.origin), net.ipFormat(forward.dest),
                    tostring(msg.msgid), tostring(conId)))
            else
                log:info(("Could not forward message: no rule; %s"):format(net.stringMessage(msg)))
            end
        else -- pass the message through to the original sender
            if messages[conId] and messages[conId][msg.msgid] then
                msg.header.conId = conId
                if msg.header.publicKey then
                    log:debug('Passed message in with public key')
                    if msg.header.encrypted and msg.body.cipher then
                        log:debug('- Message was encrypted')
                    elseif msg.header.encrypted then
                        log:warn('- Message marked as encrypted, but already decrypted')
                    end
                end
                local msgData = messages[conId][msg.msgid]
                -- if msg.header.publicKey then msg.body.publicKey = msg.header.publicKey end
                if msgData.conId then conId = msgData.conId end
                cfg.inside.modem:sendMsgAdv2(port, msg.origin, msgData.origin, msg.header, msg.body, msgData.msgid)
                log:info(("In:  %s for %s: #%s:%s"):format(net.ipFormat(msg.origin), net.ipFormat(msgData.origin),
                    tostring(msgData.msgid), tostring(conId)))
            end
        end
    end
end

local osPullEventRaw = os.pullEventRaw
local pMessages = {}
local function pullEventRaw(sFilter)
    while true do
        local event = { osPullEventRaw() }
        if event[1] == 'modem_message' then
            local _, side, port, _, message, _ = unpack(event)
            if not check(side, port, message) then 
                ---@cast message NetMessage
                local uMsgId = net.ipFormat(message.origin)
                uMsgId = uMsgId ..':'.. message.msgid
                if message.header.conId then
                    uMsgId = uMsgId ..':'.. message.header.conId
                end
                if not pMessages[uMsgId] then
                    log:debug(('msg from %s: %s'):format(side, uMsgId))
                    handlerFunc(side, port, message)
                end
                pMessages[uMsgId] = true
            end
        end
        if (not sFilter) or event[1] == sFilter then
            return unpack(event)
        end
    end
end
os.pullEventRaw = pullEventRaw