local require, netLog = ...
---@cast netLog Logger
---@cast require fun(path: string): any
local ecc = pos.require("ecc")

local certificate = {}
_G.net.certificate = certificate

certificate.available = false

---@diagnostic disable-next-line: missing-fields
local ccaCert = {} ---@type net.Certificate
local ccaFilePath = "/os/net/cca.cert"

local cache = {} ---@type {string: net.Certificate}
local cacheFilePath = "/home/.appdata/net/certificate.cache"

---Initialize the certificate module (run in net init)
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

    if cache[cert.id] then
        local cacheCert = cache[cert.id]
        for k, v in pairs(cert) do
            if type(v) == 'table' then
                if not net.encrypt.keyMatch(cacheCert[k], v) then
                    return false
                end
            end
            if cacheCert[k] ~= v then
                return false
            end
        end
        return true
    end

    local signerKey = {}
    if cert.signer == "cca" then
        signerKey = ccaCert.key
    elseif cache[cert.signer] then
        local signer = cache[cert.signer]
        if not signer.canSign then
            return false
        end
        signerKey = signer.key
    elseif cert.parent then
        if not certificate.check(cert.parent) then
            return false
        end
        if not cert.parent.canSign then
            return false
        end
        signerKey = cert.parent.key
    else
        return false
    end

    local o = {
        id = cert.id,
        origin = cert.origin,
        key = cert.key,
        canSign = cert.canSign,
        signer = cert.signer
    }
    local valid = ecc.verify(signerKey, textutils.serialise(o), cert.signature)

    if valid then
        cache[cert.id] = certificate.copy(cert)
        certificate.saveCache()
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
        if cache[cert.id] then
            return cache[cert.id].key
        elseif certificate.check(cert) then
            return cert.key
        else
            return nil
        end
    elseif msg.header.originDomain then
        for _, cert in pairs(cache) do
            if cert.origin == msg.msg.header.originDomain then
                return cert.key
            end
        end
        return msg.header.publicKey
    else
        return msg.header.publicKey
    end
end

---Copy a certificate
---@param cert net.Certificate
---@return net.Certificate
function certificate.copy(cert)
    return {
        id = cert.id,
        origin = cert.origin,
        key = cert.key,
        canSign = cert.canSign,
        signer = cert.signer,
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
---@field id string Node ID
---@field origin string? Origin name (hostname)
---@field key byteArray Node encryption public key
---@field canSign boolean? If this node may sign for others
---@field signer string Signer's Node ID
---@field signature byteArray Signature with signer's private key *(NOT SIGNED)*
---@field parent net.Certificate? Signer's certificate *(NOT SIGNED)*

certificate.init()