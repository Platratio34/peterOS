local require, netLog = ...
---@cast netLog Logger
---@cast require fun(path: string): any
local ecc = pos.require("ecc")

local certificate = {}
_G.net.certificate = certificate

certificate.available = false ---If the certificate module is available, `false` if CCA certificate could not be loaded

---@diagnostic disable-next-line: missing-fields
local ccaCert = {} ---@type net.Certificate
local ccaFilePath = "/os/net/cca.cert"

local cache = {} ---@type {string: net.Certificate} Table of NodeID to Certificate
local cacheFilePath = "/home/.appdata/net/certificate.cache"

local selfCertFilePath = "/home/.appdata/net/"

---Initialize the certificate module (ran in net init)
---@return boolean available
function certificate.init()
    if certificate.available then return true end
    if not fs.exists(ccaFilePath) then
        netLog:error("No CCA certificate found")
        return false
    end
    local ccaFile = fs.open(ccaFilePath, 'r')
    if not ccaFile then
        netLog:error("Unable to read CCA certificate")
        return false
    end
    ccaCert = textutils.unserialiseJSON(ccaFile.readAll())
    ccaFile.close()
    if not ccaCert then
        netLog:error("CCA certificate corrupted")
        return false
    end
    if fs.exists(cacheFilePath) then
        local cacheFile = fs.open(cacheFilePath, 'r')
        if not cacheFile then
            netLog:error('Could not read certificate cache')
        else
            cache = textutils.unserialiseJSON(cacheFile.readAll())
            cacheFile.close()
            if not cache then
                netLog:error('Certificate cache corrupted')
            end
        end
    end
    certificate.available = true
    return true
end

---Check if a certificate is valid
---@param cert net.Certificate
---@return boolean valid
function certificate.check(cert)
    if not certificate.available then
        error("Certificate verification unavailable", 2)
        return false
    end

    if cert.validUntil < os.epoch('utc') then
        return false
    end

    local issuerKey = {}
    if cert.issuer == "cca" or cert.id == "cca" then
        issuerKey = ccaCert.key
    elseif cert.parent then
        if not certificate.check(cert.parent) then
            return false
        end
        if cert.validUntil <= cert.parent.validUntil then -- Can not issue certificate valid after parent
            return false
        elseif not cert.parent.canSign then
            if not cert.id:ends('.'..cert.parent.id) and (not cert.canSign) then -- Must have derivative ID, and can not be general certificate issuer
                return false
            end
        end
        issuerKey = cert.parent.key
    elseif cache[cert.issuer] then
        local signer = cache[cert.issuer]
        if cert.validUntil <= signer.validUntil then -- Can not issue certificate valid after parent
            return false
        elseif not signer.canSign then
            if not cert.id:ends('.' .. signer.id) and (not cert.canSign) then -- Must have derivative ID, and can not be general certificate issuer
                return false
            end
        end
        issuerKey = signer.key
    else
        return false
    end

    local o = {
        id = cert.id,
        key = cert.key,
        canSign = cert.canSign,
        validUntil = cert.validUntil,
        issuer = cert.issuer
    }
    local valid = ecc.verify(issuerKey, textutils.serialise(o), cert.signature)

    if valid then
        local cached = cache[cert.id]
        if not cached then
            cache[cert.id] = certificate.copy(cert)
            certificate.saveCache()
        elseif cached.validUntil < cert.validUntil then
            cache[cert.id] = certificate.copy(cert)
            certificate.saveCache()
        end
    end
    return valid
end

---Get public encryption key for origin from certificate, cache, or header.
---@param msg NetMessage Message 
---@return byteArray? key Public encryption key **OR** `nil` if provided certificate could not be verified
function certificate.getKey(msg)
    if not certificate.available then
        return msg.header.publicKey
    end
    local origin = msg.header.originDomain or msg.header.rspDomain
    if msg.header.certificate then
        local cert = msg.header.certificate ---@cast cert net.Certificate
        if origin ~= cert.id then
            return nil
        elseif certificate.check(cert) then
            return cert.key
        else
            return nil
        end
    elseif origin then
        if cache[origin] then
            local cert = cache[origin]
            if cert.validUntil < os.epoch('utc') then
                return nil
            end
            return cert.key
        end
        return msg.header.publicKey
    else
        return msg.header.publicKey
    end
end

---Copy a certificate
---@param cert net.Certificate
---@return net.Certificate copy
function certificate.copy(cert)
    return {
        id = cert.id,
        key = cert.key,
        canSign = cert.canSign,
        validUntil = cert.validUntil,
        signer = cert.issuer,
        signature = cert.signature,
    }
end

---Save the certificate cache
---@return boolean saved
function certificate.saveCache()
    local cacheFile = fs.open(cacheFilePath, 'w')
    if not cacheFile then
        netLog:error("Unable to open cache file for writing")
        return false
    end
    cacheFile.write(textutils.serialiseJSON(cache))
    cacheFile.close()
    return true
end

local alreadyRenewing = {} ---@type {string: boolean}
---Add applicable self certificate to outgoing message
---@param msg NetMessage
---@return NetMessage
function certificate.addCert(msg)
    local origin = msg.header.originDomain or msg.header.rspDomain
    if not origin then
        return msg
    end
    local certPath = selfCertFilePath .. origin .. '.cert'
    if not fs.exists(certPath) then
        netLog:warn('Tried to load self certificate for `'..origin..'`, could not be found')
        return msg
    end
    local certFile = fs.open(certPath, 'r')
    if not certFile then
        netLog:error("Could not open certificate file `" .. certPath .. '`')
        return msg
    end
    local cert = textutils.unserialiseJSON(certFile.readAll()) ---@type net.Certificate?
    certFile.close()
    if not cert then
        netLog:error("Certificate file `" .. certPath .. '` corrupted')
        return msg
    end
    if cert.validUntil < os.epoch('utc') then
        netLog:warn('Certificate ' .. cert.id .. ' expired')
        return msg
    elseif cert.validUntil < os.epoch('utc') + (8.64e7) then -- one day?
        if not alreadyRenewing[cert.id] then
            netLog:warn('Certificate ' .. cert.id .. ' is going to expire within 1 day')
            local timer = os.startTimer(1)
            local timer2 = -1
            local msgId = -1
            pos.addEventHandler(function(event, handler)
                if event[1] == 'timer' and event[2] == timer then
                    msgId = net.send(net.standardPorts.network, cert.issuer, 'certRenew', cert)
                    if msgId == -1 then
                        netLog:warn("Unable to renew certificate " .. cert.id..': send error')
                        handler:unregister()
                    else
                        timer2 = os.startTimer(10)
                    end
                elseif event[1] == 'timer' and event[2] == timer2 then
                    netLog:warn("Unable to renew certificate " .. cert.id .. ': timeout')
                    handler:unregister()
                elseif event[1] == 'net_message' then
                    local m = event[2] ---@type NetMessage
                    if m.port ~= net.standardPorts.network or m.msgid ~= msgId or m.header.type ~= 'certRenew' then
                        return
                    end
                    if m.header.failed then
                        netLog:warn("Unable to renew certificate " .. cert.id .. ': issuer replied failed')
                        return
                    end 
                    handler:unregister()
                    local f = fs.open(certPath, 'w')
                    if not f then
                        netLog:warn("Unable to renew certificate " .. cert.id .. ': could not write new certificate')
                        return
                    end
                    f.write(textutils.serialiseJSON(m.body))
                    f.close()
                    netLog:info("Renewed certificate "..cert.id)
                end
            end, {'timer','net_message'}, 'certRenew-'..cert.id)
        end
    end
    msg.header.certificate = cert
    if msg.header.publicKey and not net.encrypt.keyMatch(msg.header.publicKey, cert.key) then
        netLog:warn('Outgoing message with certificate for '..cert.id..': Certificate key does not match public key in header')
    end
    return msg
end

---Make a new certificate. **RETURNS `nil` IF SELF CERTIFICATE CANNOT SIGN FOR REQUESTED**
---@param id string Requested Node ID
---@param key byteArray Public key for requested certificate
---@param canSign boolean If the requested certificate can sign arbitrarily **CAN ONLY BE TRUE SELF CERTIFICATE CAN SIGN ARBITRARILY**
---@param validUntil number UTC epoch millisecond time for certificate expiration time
---@param issuer string Issuer self cert Node ID
---@return net.Certificate|nil newCert **OR** `nil` if certificate could not be created
function certificate.makeCertificate(id, key, canSign, validUntil, issuer)
    local certPath = selfCertFilePath .. issuer .. '.cert'
    if not fs.exists(certPath) then
        netLog:warn('Tried to load self certificate for `' .. issuer .. '`, could not be found')
        return nil
    end
    local certFile = fs.open(certPath, 'r')
    if not certFile then
        netLog:error("Could not open certificate file `" .. certPath .. '`')
        return nil
    end
    local cert = textutils.unserialiseJSON(certFile.readAll()) ---@type net.Certificate?
    certFile.close()
    if not cert then
        netLog:error("Certificate file `" .. certPath .. '` corrupted')
        return nil
    elseif cert.validUntil < os.epoch('utc') then
        netLog:warn('Certificate ' .. cert.id .. ' expired')
        return nil
    end
    if not cert.canSign then
        if canSign then
            netLog:warn(
                'Tried to sign for invalid new signature; Arbitrary certificate requested, but selected parent can not create')
            return nil
        elseif not id:ends('.' .. cert.id) then
            netLog:warn(
                'Tried to sign for invalid new signature; Invalid new ID, must be derivative for selected parent')
            return nil
        end
    elseif cert.validUntil < validUntil then
        netLog:warn(
            'Tried to sign for invalid new signature; Expiration was after selected parent, expiration was moved to parent\'s')
        validUntil = cert.validUntil
    end
    local newCert = {
        id = id,
        key = key,
        canSign = canSign,
        validUntil = validUntil,
        issuer = cert.id
    }
    newCert.signature = net.encrypt.sign(textutils.serialise(newCert))
    ---@cast newCert net.Certificate

    newCert.parent = cert
    return newCert
end

---Setup a certificate renewal server based on the selected self certificate
---@param issuer string Issuing certificate ID for renewals
---@param period number? Period to renew certificates for in milliseconds. (Defaults to 30 days)
---@param arbitrary boolean? If it should renew arbitrary certificates
---@return number handlerId Message handler ID for `net.unregisterMsgHandler()` *OR* -1 if the server could not be started
function certificate.setupCertServer(issuer, period, arbitrary)
    period = period or (1000 * 60 * 60 * 24 * 30)
    arbitrary = arbitrary or false

    local validCerts = {}
    local validCertPath = selfCertFilePath .. issuer .. '.json'
    if not fs.exists(validCertPath) then
        netLog:error('Could not start certificate server for issuer `' .. issuer .. '`: valid list file could not be found')
        return -1
    end
    local validCertFile = fs.open(validCertPath, 'r')
    if not validCertFile then
        netLog:error('Could not start certificate server for issuer `' .. issuer .. '`: valid list file could not be opened')
        return -1
    end
    validCerts = textutils.unserialiseJSON(validCertFile.readAll())
    validCertFile.close()
    if not validCerts then
        netLog:error('Could not start certificate server for issuer `' .. issuer .. '`: valid list file was corrupted')
        return -1
    end
    return net.registerMsgHandler(function(msg)
        if msg.header.domain ~= issuer then
            return
        end
        if msg.port == net.standardPorts.network and msg.type == 'certRenew' then
            local req = msg.body ---@cast req net.Certificate
            if not validCerts[req.id] then
                msg:reply(net.standardPorts.network, { type = "certRenew", originDomain = issuer, failed = 'true' }, {})
                return
            end
            if (msg.header.certificate.id ~= req.id) or ( req.canSign and not (msg.header.certificate.canSign and arbitrary) ) then
                msg:reply(net.standardPorts.network, { type = "certRenew", originDomain = issuer, failed = 'true' }, {})
                return
            end
            local newCert = certificate.makeCertificate(req.id, req.key, req.canSign, req.validUntil + period, issuer)
            if not newCert then
                msg:reply(net.standardPorts.network, {type="certRenew",originDomain=issuer,failed='true'}, {})
                return
            end
            msg:reply(net.standardPorts.network, {type="certRenew",originDomain=issuer}, newCert)
        end
    end)
end

---@class net.Certificate
---@field id string Node ID (domain is applicable)
---@field key byteArray Node encryption public key
---@field canSign boolean? If this node may sign for **ANY** others, if absent or false, may only sign for derivatives
---@field validUntil number Certificate expiration time in UTC epoch milliseconds (check with `os.epoch('utc')`)
---@field issuer string Issuer's Node ID
---@field signature byteArray Signature with issuer's private key *(NOT SIGNED)*
---@field parent net.Certificate? Issuer's certificate (and parents) *(NOT SIGNED)*

certificate.init()