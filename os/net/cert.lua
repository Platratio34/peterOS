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
    if cert.issuer == "cca" then
        issuerKey = ccaCert.key
    elseif cert.parent then
        if not certificate.check(cert.parent) then
            return false
        end
        if not cert.parent.canSign then
            if not cert.id:ends('.'..cert.parent.id) and cert.validUntil <= cert.parent.validUntil and not cert.canSign then -- not derivate certificate
                return false
            end
        end
        issuerKey = cert.parent.key
    elseif cache[cert.issuer] then
        local signer = cache[cert.issuer]
        if signer.validUntil < os.epoch('utc') then
            return false
        end
        if not signer.canSign then
            if not cert.id:ends('.'..signer.id) and cert.validUntil <= signer.validUntil and not cert.canSign then -- not derivate certificate
                return false
            end
        end
        issuerKey = signer.key
    else
        return false
    end

    local o = {
        id = cert.id,
        origin = cert.origin,
        key = cert.key,
        canSign = cert.canSign,
        signer = cert.issuer
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
    if msg.header.certificate then
        local cert = msg.header.certificate ---@cast cert net.Certificate
        if msg.header.originDomain ~= cert.id then
            return nil
        elseif certificate.check(cert) then
            return cert.key
        else
            return nil
        end
    elseif msg.header.originDomain then
        if cache[msg.msg.header.originDomain] then
            local cert = cache[msg.msg.header.originDomain]
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

---@class net.Certificate
---@field id string Node ID (domain is applicable)
---@field key byteArray Node encryption public key
---@field canSign boolean? If this node may sign for **ANY** others, if absent or false, may only sign for derivatives
---@field validUntil number Certificate expiration time in UTC epoch milliseconds (check with `os.epoch('utc')`)
---@field issuer string Issuer's Node ID
---@field signature byteArray Signature with issuer's private key *(NOT SIGNED)*
---@field parent net.Certificate? Issuer's certificate (and parents) *(NOT SIGNED)*

certificate.init()