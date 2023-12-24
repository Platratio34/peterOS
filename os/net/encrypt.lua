local ecc = pos.require("ecc")

local keyFilename = "/home/.appdata/net/key.key"
local keyset = nil

local keys = {}

local log = pos.Logger('net-encrypt.log')

---Sets up encryption module
local function setup()
    if keyset ~= nil then
        return
    end
    if fs.exists(keyFilename) then
        local f = fs.open(keyFilename, "r")
        if not f then
            log:error('Unable to read from key file')
            return
        end
        keyset = textutils.unserialiseJSON(f.readAll())
        f.close()
    end
    if keyset == nil then
        log:info('No keyset found, creating one')
        local privateKey, publicKey = ecc.keypair(ecc.random.random())
        keyset = {
            private = privateKey,
            public = publicKey,
        }
        local f = fs.open(keyFilename, "w")
        if not f then
            log:error('Unable to write to key file')
            return
        end
        f.write(textutils.serialiseJSON(keyset))
        f.close()
    end
    if keyset == nil then
        log:error('Unable to create key pair')
        return
    end
    log:info('Keypair loaded')
end

---Encrypt data
---@param data any Data to encrypt
---@param public string|byteArray Receiver's public key
---@return byteArray cyphertext Encrypted data
---@return byteArray signature Signature
local function encrypt(data, public)
    setup()
    local shared = nil
    if keys[public] ~= nil then
        shared = keys[public]
    else
        shared = ecc.exchange(keyset.private, public)
        keys[public] = shared
    end

    if type(data) == "table" then
        data = "table:"..textutils.serialise(data)
    end
    local ciphertext = ecc.encrypt(data, shared)
    local signature = ecc.sign(keyset.private, ciphertext)
    if not ciphertext then
        log:error('Ciphertext was null')
    end
    return ciphertext, signature
end

---Decrypt data
---@param cipher byteArray Cyphertext encrypted with our public key
---@param sig byteArray Signature
---@param public string|byteArray Sender's public key
---@return boolean suc If the signature matched and decryption was successful
---@return any data Original unencrypted data 
local function decrypt(cipher, sig, public)
    setup()
    local shared = nil
    if keys[public] ~= nil then
        shared = keys[public]
    else
        shared = ecc.exchange(keyset.private, public)
        keys[public] = shared
    end

    if not ecc.verify(public, cipher, sig) then
        return false, nil
    end
    
    local data = tostring(ecc.decrypt(cipher, shared))
    if string.start(data,"table:") then
        local t = textutils.unserialise(string.sub(data, 7))
        if not t then
            log:error('Malformed body: '..data)
            return true, nil
        end
        data = t
    end
    return true, data
end

---Returns our public key
---@return byteArray publicKey Local public key
local function getPublicKey()
    setup()
    return keyset.public
end

local function keyMatch(key1, key2)
    for i,v in pairs(key1) do
        if key2[i] ~= v then
            return false
        end
    end
    return true
end

net.encrypt = {
    setup = setup,
    encrypt = encrypt,
    decrypt = decrypt,
    getPublicKey = getPublicKey,
    keyMatch = keyMatch
}