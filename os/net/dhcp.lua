-- local Logger = pos.require('logger')
local log = pos.Logger('/home/.pgmLog/dhcp.log')
log:setLevel(pos.LoggerLevel.INFO)
pos.require("net.rttp")
local sha256 = pos.require("hash.sha256")
pos.require('net.rtml')


local cfg = {
    mask = 0xffff0000,          -- Subnet mask, Def: 255.255.0.0
    baseAddr = 0xc0a80000,      -- Base address of the range of addresses the DHCP and give out, Def: Private range 192.168.0.0/16
    addr = 0xc0a80000,          -- IP address of the DHCP on the local network, Def: 192.168.0.0
    addrTbl = {                 -- Table of standard addresses
        defGateway = 0xc0a80001, -- Default Gateway (NAT), Def: 192.168.0.1
        dns = 0xc0a80000,       -- Domain Name Server, Def: 192.168.0.0 (this DHCP)
    },
    global = false,             -- If it is a local or global DHCP
    adminPass = 'admin',        --- Admin password
}
local cfgPath = "/home/dhcp.cfg"
local config = pos.Config(cfgPath, cfg, true)
if not config.loaded then
    error('Unable to load config at ' .. cfgPath)
    return
end
cfg = config.data
-- if not fs.exists(cfgPath) then
--     local f = fs.open(cfgPath, "w")
--     if f == nil then
--         error("Unable to write to config at " .. cfgPath, 0)
--         return
--     end
--     f.write(textutils.serialiseJSON(cfg))
--     f.close()
-- else
--     local f = fs.open(cfgPath, "r")
--     if f == nil then
--         error("Unable to read to config at " .. cfgPath, 0)
--         return
--     end
--     cfg = textutils.unserialiseJSON(f.readAll())
--     if cfg == nil then
--         error("Config corrupted", 0)
--         return
--     end
--     f.close()
-- end

-- log:info(cfg.addr)
if not net.setup(nil, cfg.addr) then
    error("Network module setup error")
end

local function allowedAddr(ip)
    if ip < 0x0 or ip > 0xffffffff then -- not in IPV4 range
        return false
    end
    if ip >= 0xa9fe0000 and ip <= 0xa9feffff then -- not link local 169.254.0.0/16
        return false
    end
    if ip >= 0xe0000000 and ip <= 0xef000000 then -- not multicast 224.0.0.0/4
        return false
    end
    if ip >= 0x7f000000 and ip <= 0x7fffffff then -- not loopback 127.0.0.0/8
        return false
    end
    if cfg.global then
        if ip >= 0xc0000000 and ip <= 0xc00000ff then -- not private 192.0.0.0/24
            return false
        end
        if ip >= 0xc0a80000 and ip <= 0xc0a8ffff then -- not private 192.168.0.0/16
            return false
        end
        if ip >= 0xac100000 and ip <= 0xac1fffff then -- not private 172.16.0.0/12
            return false
        end
        if ip >= 0x0a000000 and ip <= 0x0affffff then -- not private 10.0.0.0/8
            return false
        end
    end
    return true
end
local function generateIP()
    local ip = math.random(2, 0xffffffff - cfg.mask - 1)
    ip = ip + cfg.baseAddr
    while not allowedAddr(ip) do
        log:debug(net.ipFormat(ip) .. " was bad")
        -- ip = math.random(cfg.baseAddr + 2, cfg.baseAddr + (0xffffffff - cfg.mask))
        ip = math.random(2, 0xffffffff - cfg.mask - 1)
        ip = ip + cfg.baseAddr
        sleep(0)
    end
    return ip
end

local leases = {} ---@type table<string, DHCPLease>
local ips = {}
ips[cfg.addr] = { time = 9e99 }
ips[cfg.addrTbl.defGateway] = { time = 9e99 }
ips[cfg.addrTbl.dns] = { time = 9e99 }
local leasesPath = "/home/dhcp/leases.json"
if fs.exists(leasesPath) then
    local f = fs.open(leasesPath, "r")
    if f == nil then
        error("Unable to open lease file")
        return
    end
    leases = textutils.unserialiseJSON(f.readAll())
    f.close()
    if not leases then
        error('Lease file corrupted')
        return
    end
    for hw, lease in pairs(leases) do
        if type(lease.ip) == 'string' then
            lease.ip = net.ipToNumber(lease.ip)
        end
        if lease.time == -1 or lease.time > os.clock() then
            ips[lease.ip] = lease
        else
            leases[hw] = nil
        end
    end
end

-- Table of domain names to IPs.
-- Formatted {ip, time, port, type}.
-- Type can be ["lan","com"."gov"."org",...]
local dns = {} ---@type table<string, DNSRecord>
local remoteDNS = {} ---@type table<string, DNSRecord> DNS records from remote servers
local dnsPath = "/home/dhcp/dns.json"
if fs.exists(dnsPath) then
    log:info("Loading DNS File")
    local f = fs.open(dnsPath, "r")
    if f == nil then
        error("Unable to read DNS file", 0)
    end
    dns = textutils.unserialiseJSON(f.readAll())
    f.close()
    if dns == nil then
        error("DNS file corrupted")
        dns = {}
    end
    ---@cast dns table<string, DNSRecord>
    for _, record in pairs(dns) do
        if type(record.ip) == "string" then
            record.ip = net.ipToNumber(record.ip)
        end
    end
end

local function save()
    local f = fs.open(leasesPath, "w")
    if f == nil then
        error("Unable to open lease file")
        return
    end
    local tl = {}
    for n, record in pairs(leases) do
        local tr = {}
        for k, v in pairs(record) do
            if k == 'ip' then
                tr[k] = net.ipFormat(v)
            else
                tr[k] = v
            end
        end
        tl[n] = tr
    end
    local t = textutils.serialiseJSON(tl)
    t = string.gsub(t, '},', '},\n')
    f.write(t)
    f.close()
end
local function saveDns()
    local f = fs.open(dnsPath, "w")
    if f == nil then
        error("Unable to open lease file")
        return
    end
    local tDns = {}
    for n, record in pairs(dns) do
        local tr = {}
        for k, v in pairs(record) do
            if k == 'ip' then
                tr[k] = net.ipFormat(v)
            else
                tr[k] = v
            end
        end
        tDns[n] = tr
    end
    local t = textutils.serialiseJSON(tDns)
    t = string.gsub(t, '},', '},\n')
    f.write(t)
    f.close()
end

local function getDNSRecord(domain)
    if dns[domain] then
        return dns[domain]
    elseif remoteDNS[domain] then
        return remoteDNS[domain]
    end
    return nil
end

math.randomseed(os.epoch())

net.open(10000) -- open network port
net.open(10080) -- open RTTP port
net.open(10081) -- open RTTPS port

-- local logPath = "/home/dhcp.log"
-- local function clearLog()
--     local f = fs.open(logPath, "w")
--     if f == nil then
--         return
--     end
--     f.write("DHCP Log")
--     f.close()
-- end
-- clearLog()
-- local printLog = false
-- local function log(str)
--     if printLog then
--         print(str)
--     end
--     local f = fs.open(logPath, "a")
--     if f == nil then
--         return
--     end
--     f.write(str.."\n")
--     f.close()
-- end

local ADMIN_PASS = sha256.hash(cfg.adminPass)

local sessionTokens = {}
local sessionTokenTime = 1000*60*10 --- Session token expire time: 10m

---Handle an RTTP message
---@param msg RttpMessage
local function rttpMsgHandler(msg)
    log:debug(rttp.stringMessage(msg))
    local origin = msg.origin
    if msg.header.conId then
        origin = origin .. ':' .. msg.header.conId
    end
    
    local path = msg.header.path

    if msg.header.method == 'POST' then
        if path == '/' and msg.body.type == 'BUTTON_SUBMIT' then
            if msg.body.vals.user == 'admin' and sha256.hash(msg.body.vals.pass) == ADMIN_PASS then
                local token = sessionTokens[origin]
                if not token then
                    token = {
                        time = os.epoch('utc') + sessionTokenTime,
                        token = sha256.hash(origin .. string.randomString(8))
                    }
                    sessionTokens[origin] = token
                end
                rttp.reply(msg, rttp.responseCodes.movedTemporarily, 'text/plain', "Valid Login",
                    { redirect = '/panel', cookies = { ['dnsToken'] = token.token } })
            else
                rttp.reply(msg, rttp.responseCodes.movedTemporarily, 'text/plain', "Invalid Login",
                    { redirect = '/loginfailed', cookies = { ['dnsToken'] = '' } })
            end
            return
        end
    elseif msg.header.method == 'GET' then
        if path == '/' then
            rttp.reply(msg, rttp.responseCodes.okay, 'table/rtml', {
                { type = "TEXT",   x = 2, y = 2, text = "DHCP/DNS Control", color = colors.white },

                { type = "TEXT",   x = 3, y = 5, text = "User:" },
                { type = "INPUT",  x = 8, y = 5, len = 16,                  name = "user" },
                { type = "TEXT",   x = 3, y = 6, text = "Pass:" },
                { type = "INPUT",  x = 8, y = 6, len = 16,                  name = "pass",       hide = true },
                { type = "BUTTON", x = 8, y = 7, text = "Login",            action = "SUBMIT" }
            })
            return
        elseif path == '/loginfailed' then
            rttp.reply(msg, rttp.responseCodes.okay, 'table/rtml', {
                { type = "TEXT", x = 2, y = 2, text = "DHCP/DNS Control", color = colors.white },

                { type = "TEXT", x = 3, y = 5, text = "Login Invalid" },
                { type = "LINK", x = 3, y = 6, text = "Login",            href = '/' }
            })
            return
        elseif path == '/loginfirst' then
            rttp.reply(msg, rttp.responseCodes.okay, 'table/rtml', {
                { type = "TEXT", x = 2, y = 2, text = "DHCP/DNS Control", color = colors.white },

                { type = "TEXT", x = 3, y = 5, text = "Login First", color = colors.red },
                { type = "LINK", x = 3, y = 6, text = "Login",            href = '/' }
            })
            return
        elseif path == '/logout' then
            sessionTokens[origin] = nil
            rttp.reply(msg, rttp.responseCodes.movedTemporarily, 'text/plain', "Logging out",
                { redirect = '/', cookies = { ['dnsToken'] = '' } })
        end
    end

    local token = nil
    if msg.header.cookies then
        token = msg.header.cookies['dnsToken']
    end
    if not sessionTokens[origin] or sessionTokens[origin].token ~= token then
        rttp.reply(msg, rttp.responseCodes.movedTemporarily, 'text/plain', 'Login first', { redirect = '/loginfirst', cookies = { ['dnsToken'] = '' } })
        return
    end
    if sessionTokens[origin].time < os.epoch('utc') then
        sessionTokens[origin] = nil
        rttp.reply(msg, rttp.responseCodes.movedTemporarily, 'text/plain', 'Token expired', { redirect = '/loginfirst', cookies = { ['dnsToken'] = '' } })
        return
    end
    sessionTokens[origin].time = os.epoch('utc') + sessionTokenTime

    if msg.header.method == 'POST' then
        if path == '/panel/dns/add' then
            if msg.body.type == 'BUTTON_SUBMIT' then
                local recordName = msg.body.vals.name
                local port = msg.body.vals.port
                if port == '' then
                    port = '*'
                elseif tonumber(port) then
                    port = tonumber(port) ---@cast port number
                end
                local nameSplit = string.split(recordName, '.')
                local record = { ---@type DNSRecord
                    ip = net.ipToNumber(msg.body.vals.host),
                    port = port,
                    type = nameSplit[#nameSplit],
                    time = os.epoch(),
                }
                dns[recordName] = record
                saveDns()
                rttp.reply(msg, rttp.responseCodes.movedTemporarily, 'text/plain', "Record Added",
                    { redirect = '..' })
                return
            end
        elseif path == '/panel/dns/remove' then
            if msg.body.type == 'BUTTON_PUSH' then
                log:info('Removed record for '..msg.body.id)
                dns[msg.body.id] = nil
                saveDns()
                rttp.reply(msg, rttp.responseCodes.movedTemporarily, 'text/plain', "Record Removed",
                    { redirect = '' })
                return
            end
        end
        rttp.reply(msg, rttp.responseCodes.badRequest, 'text/plain', 'Invalid path for POST')
        return
    elseif msg.header.method == 'GET' then
        if path == '/panel' then
            local body = net.rtml.createContext()
            body:addText(2, 2, "DHCP/DNS Control Panel", colors.white)
            body:addLink(4, 3, "Logout", "/logout")

            body:addLink(2, 5, 'DHCP', 'dhcp')
            body:addLink(2, 6, 'DNS', 'dns')
            rttp.reply(msg, rttp.responseCodes.okay, 'table/rtml', body.elements)
            return
        elseif path == '/panel/dns' then
            local body = net.rtml.createContext()
            body:addText(2, 2, "DNS Control Panel", colors.white)
            body:addLink(4, 3, "Panel", "/panel")

            local y = 5
            body:addText(2, y, 'DNS Records')
            body:addLink(15, y, 'Add Record', 'add')
            y = y + 2
            body:addText(2, y, 'Name')
            body:addText(20, y, 'Port')
            body:addText(28, y, 'Host')

            for name, record in pairs(dns) do
                y = y + 1
                body:addText(2, y, name)
                body:addText(20, y, record.port..'')
                body:addText(28, y, net.ipFormat(record.ip))
                local btn = net.rtml.createButton(44, y, 'Remove', net.rtml.BUTTON_ACTION_PUSH)
                btn.id = name
                btn.href = 'remove'
                btn.bgColor = colors.red
                body:addElement(btn)
            end
            rttp.reply(msg, rttp.responseCodes.okay, 'table/rtml', body.elements)
            return
        elseif path == '/panel/dns/add' then
            local body = net.rtml.createContext()
            body:addText(2, 2, "DNS Add Record", colors.white)
            body:addLink(4, 3, "DNS Panel", "/panel/dns")

            body:addText(4, 5, 'Name:')
            body:addInput(9, 5, 16, 'name')
            
            body:addText(4, 6, 'Host:')
            body:addInput(9, 6, 16, 'host')
            
            body:addText(4, 7, 'Port:')
            body:addInput(9, 7, 16, 'port')

            body:addSubmitButton(9, 9, 'Add')
            
            rttp.reply(msg, rttp.responseCodes.okay, 'table/rtml', body.elements)
            return
        elseif path == '/panel/dhcp' then
            local body = net.rtml.createContext()
            body:addText(2, 2, "DHCP Control Panel", colors.white)
            body:addLink(4, 3, "Panel", "/panel")

            local y = 5
            body:addText(2, y, 'DHCP Leases')
            -- body:addLink(15, y, 'Add Record', 'add')
            y = y + 2
            body:addText(2, y, 'IP')
            body:addText(18, y, 'Hostname')
            body:addText(32, y, 'HW Address')

            for _, record in pairs(leases) do
                y = y + 1
                body:addText(2, y, net.ipFormat(record.ip))
                body:addText(18, y, record.hostname or '')
                body:addText(31, y, ' '..record.owner)
            end
            rttp.reply(msg, rttp.responseCodes.okay, 'table/rtml', body.elements)
            return
        end
        rttp.reply(msg, rttp.responseCodes.notFound, 'text/plain', 'Path not found on server')
        return
    end

    rttp.reply(msg, rttp.responseCodes.methodNotAllowed, 'text/plain', 'Invalid method, must be GET or POST')
end

local mi = -1
local function handler(msg)
    log:debug('MSG')
    ---@cast msg NetMessage
    if not (msg.dest == cfg.addr or (msg.dest == -1 and msg.header.type == "net.ip.req") or (msg.dest == -1 and msg.header.type == "net.dns.get")) then
        return
    end
    if not (msg.port == 10000 or msg.port == 10080 or msg.port == 10081) then
        return
    end
    -- local msg = net.waitForMsgAll(function(port, msg)
    --     if msg.dest == cfg.addr then
    --         if port == 10000 or port == 10080 or port == 10081 then
    --             return false
    --         end
    --     elseif msg.dest == -1 and msg.header.type == "net.ip.req" then
    --         return false
    --     end
    --     return true
    -- end, -1)
    -- if msg == nil then
    --     return
    -- end

    mi = mi + 1
    log:debug("MSG " .. mi .. " - " .. net.stringMessage(msg))

    local sysTime = os.epoch()

    if msg.header.type == "net.ip.req" then -- Request for DHCP server
        local lease = leases[msg.origin]

        if lease ~= nil and (lease.time == -1 or lease.time > sysTime) then -- If there is already a lease for this computer
            lease.time = sysTime + 9e99 + (8.64e7 * 7)
            if msg.body.hostname ~= nil then
                lease.hostname = msg.body.hostname
            end
            log:info("Tendering pre-leased ip " .. net.ipFormat(lease.ip) .. " to " .. lease.owner)
            net.reply(10000, msg, { type = "net.ip.req.return" }, { ip = lease.ip, mask = cfg.mask, time = lease.time })
            save()
            return
        end

        -- Generate a new lease for the computer

        lease = {
            -- time = sysTime + (8.64e7 * 0.5), -- expiration time of the lease
            time = -1,
            owner = msg.origin, -- owners hardware address
            ip = generateIP(),  -- lease IP
        }
        local m = nil
        while m ~= "timeout" do
            while ips[lease.ip] ~= nil and (ips[lease.ip].time == -1 or ips[lease.ip].time > sysTime) do
                lease.ip = generateIP()
            end
            net.send(10000, lease.ip, "net.ip.check", {})
            m = net.waitForMsgAdv(10000, 1, function(message)
                if message.header.type == "net.ip.found" then
                    if message.origin == lease.ip then
                        log:info("Someone already had ip " .. net.ipFormat(lease.ip))
                        return true
                    end
                end
                return false
            end)
        end
        log:info("Tendering ip " .. net.ipFormat(lease.ip) .. " for " .. lease.owner)
        net.reply(10000, msg, { type = "net.ip.req.return" }, { ip = lease.ip, mask = cfg.mask, time = lease.time })
        leases[msg.origin] = lease
        ips[lease.ip] = lease
        save()
    elseif msg.header.type == "net.ip.acp" then -- IP accept message
        local lease = leases[msg.origin]

        if lease ~= nil and (lease.time == -1 or lease.time > sysTime) then
            -- lease.time = sysTime + (8.64e7*7)
            lease.time = -1
            -- if msg.body.hostname ~= nil then
            --     lease.hostname = msg.body.hostname
            -- end
            if msg.body.hostname ~= nil then       -- if the computer provided a hostname, add it to the lease and add it to the DNS table as a lan address
                lease.hostname = msg.body.hostname -- lease owner hostname
            end
            if lease.hostname then
                if not cfg.global then
                    dns[lease.hostname .. ".lan"] = {
                        ip = lease.ip,
                        time = sysTime,
                        port = "*",
                        type = "lan",
                    }
                    saveDns()
                end
            end
            net.reply(10000, msg, { type = "net.ip.acp.return" },
                { ip = lease.ip, mask = cfg.mask, time = lease.time, addrTbl = cfg.addrTbl })
            save()
            return
        end
        lease = {
            -- time = sysTime + (8.64e7 * 7),
            time = -1,
            owner = msg.origin,
            ip = generateIP(),
        }
        if msg.body.hostname ~= nil then
            lease.hostname = msg.body.hostname
            if not cfg.global then
                dns[lease.hostname .. ".lan"] = {
                    ip = lease.ip,
                    time = sysTime,
                    port = "*",
                    type = "lan",
                }
                saveDns()
            end
        end
        while ips[lease.ip] ~= nil and ips[lease.ip].time > sysTime do
            lease.ip = generateIP()
        end
        net.reply(10000, msg, { type = "net.ip.acp.return" },
            { ip = lease.ip, mask = cfg.mask, time = lease.time, addrTbl = cfg.addrTbl })
        leases[msg.origin] = lease
        ips[lease.ip] = lease
        save()
    elseif msg.header.type == "net.ip.renew" then -- Renew DHCP Lease
        local lease = leases[msg.body.hwaddr]

        if lease ~= nil then
            if (lease.time == -1 or lease.time > sysTime) then
                -- lease.time = sysTime + 9e99 + (8.64e7 * 7)
                lease.time = -1
                net.reply(10000, msg, { type = "net.ip.renew.return" },
                    { action = "renewed", ip = lease.ip, mask = cfg.mask, time = lease.time, addrTbl = cfg.addrTbl })
                log:info("IP lease renewed for " .. lease.ip)
                save()
                return
            end
        else
            if ips[msg.origin] == nil or (ips[msg.origin].time < os.clock() and ips[msg.origin].time > -1) then
                lease = {
                    -- time = sysTime + 9e99 + (8.64e7 * 7),
                    time = -1,
                    owner = msg.body.hwaddr,
                    ip = msg.origin,
                }
                net.reply(10000, msg, { type = "net.ip.renew.return" },
                    { action = "renewed", ip = lease.ip, mask = cfg.mask, time = lease.time, addrTbl = cfg.addrTbl })
                log:info("IP lease renewed for " .. lease.ip)
                leases[msg.body.hwaddr] = lease
                ips[msg.origin] = lease
                save()
                return
            else
                net.reply(10000, msg, { type = "net.ip.renew.return" }, { action = "reget" })
                log:info("IP in use twice: " .. msg.origin)
            end
        end
    elseif msg.header.type == "net.dns.get" then -- DNS resolve domain names
        local domain = msg.body.domain
        local record = getDNSRecord(domain)
        log:debug('Received DNS request for ' .. domain)
        if record == nil then
            -- net.send(10000, 0x00000001, "net.dns.get", { domain = domain })
            -- log:info("Trying to get '"..domain.."' from global DNS")
            -- local m = net.waitForMsgAdv(10000, 2, function(message)
            --     return message.dest == cfg.addr and message.type == "net.dns.get.return"
            -- end)
            local rsp = net.sendSync(10000, 0x00000001, "net.dns.get", { domain = domain })

            if type(rsp) ~= "string" and rsp.header.code ~= "not_found" then
                local rec = rsp.body ---@cast rec DNSRecord
                remoteDNS[domain] = rec
                log:info('Adding record: ' .. textutils.serialiseJSON(rsp.body))
                msg:reply(10000, { type = "net.dns.get.return", code = "found", hostname = domain }, rsp.body)
                log:info("Returned ip " .. net.ipFormat(remoteDNS[domain].ip) .. " for '" .. domain .. "'")
                return
            end

            msg:reply(10000, { type = "net.dns.get.return", code = "not_found" }, {})
            log:info("Could not find '" .. domain .. "'")
            return
        end

        msg:reply(10000, { type = "net.dns.get.return", code = "found", hostname = domain }, record)
        log:info("Returned ip " .. net.ipFormat(record.ip) .. " for '" .. domain .. "'")
    elseif msg.header.type == 'net.ip.changeHost' then
        local src = msg.origin
        local hostname = msg.body.hostname
        if not cfg.global then
            dns[hostname .. ".lan"] = {
                ip = src,
                time = sysTime,
                port = "*",
                type = "lan",
            }
            saveDns()
        end
    elseif msg.header.type == "rttp" then -- Access DHCP/DNS webpage
        ---@cast msg RttpMessage
        -- if msg.header.method == "GET" then
        --     log:info("Received RTTP GET message")
        --     net.reply(10080, msg, { type = "rttp", method = "RETURN", content_type = "text/plain" },
        --         "DHCP: " .. net.getHostname())
        -- end
        rttpMsgHandler(msg)
    end
end

log:info("DHCP/DNS started:")
log:info("IP: " .. net.ipFormat(cfg.addr))
log:info("Mask: " .. net.ipFormat(cfg.mask))
log:info("Base Address: " .. net.ipFormat(cfg.baseAddr))
log:info("Default Gateway: " .. net.ipFormat(cfg.addrTbl.defGateway))
-- while true do
--     loop()
-- end
local handlerId = net.registerMsgHandler(handler)
log:info('HandlerId: ' .. handlerId)

_G.net.dhcp = _G.net.dhcp or {}
net.dhcp.handlerId = handlerId

---@class DNSRecord Domain name record
---@field ip string|number IP address
---@field time number Last update time
---@field port string|number Port filter
---@field type string Domain type

---@class DHCPLease IP lease record
---@field ip string|number IP address
---@field time number Renew time
---@field hostname string|nil Device requested hostname
---@field owner string HW address
