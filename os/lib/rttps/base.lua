local rsa = pos.require("rsa.rsa-crypt")
-- local ecc = pos.require("ecc")

local function send(modem, origin, host, path, method, code, body, headers)
    -- print(origin.." "..host)
    local msg = {
        type = "rttps",
        origin = origin,
        host = host,
        path = path,
        method = method,
        code = code,
        body = body,
        header = headers
    }
    -- print("Sending message: ")
    -- for k,v in pairs(msg) do
    --     print("  "..k.." = "..tostring(v))
    -- end
    modem.transmit(80, 80, msg)
end

local function encode(body, publicKey)
    local bdy = textutils.serialiseJSON(body)
    local res = rsa.bytesToNumber(rsa.stringToBytes(bdy), 8*512, 8)
    local encrypted = rsa.crypt(publicKey, res)
    return {
        shared = publicKey.shared,
        data = encrypted
    }
end

local function decode(body, privateKey)
    if body.shared ~= privateKey.shared then
        return nil
    end
    local decrypted = rsa.crypt(privateKey, rsa.stringToBytes(body.data))
    local decryptedBytes = rsa.numberToBytes(decrypted, 8*512, 8)
    return textutils.unserialiseJSON(rsa.bytesToString(decryptedBytes))
end

return {
    send = send,
    encode = encode,
    decode = decode,
}