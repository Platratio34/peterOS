---@class LocalUser pOS User object
---@field perm nil|{str:boolean} FILE ONLY permission dictionary
---@field protected _perm {str:boolean} User permissions
---@field name string User name
---@field pasH string Password hash (SHA-256)
local LocalUser = {
    perm = {},
    _perm = {}
}
local LocalUserMT = {
    __index = LocalUser,
}
local fsOpen, osLog, require = unpack({ ... })
local sha256 = require("hash.sha256")

---Create a new LocalUser with name, password, and permissions
---@constructor LocalUser
---@param name string
---@param pass string
---@param perm string|table
---@return nil
function LocalUserMT.__call(name, pass, perm)
    if fs.exists(name .. '.userDat') then
        osLog:warn('Tried to create a new user "' .. name .. '", but it already existed')
        return nil
    end
    if type(perm) ~= 'table' then
        perm = { perm }
    end
    local perm2 = {}
    for k, v in pairs(perm) do
        if type(k) == 'integer' then
            perm2[v] = true
        elseif type(k) == 'string' then
            perm2[k] = v
        end
    end
    perm = perm2
    local user = {}
    setmetatable(user, LocalUserMT) ---@cast user LocalUser
    user:__init__(name, pass, perm)
    user:save()
    osLog:info('Created new user "' .. name .. '"')
    return user
end

---Initilize a new LocalUser
---@param name string username
---@param pass string password
---@param perm {str: boolean} permission tree
function LocalUser:__init__(name, pass, perm)
    self.name = name
    self.pasH = sha256.hash(pass)
    self._perm = perm
end

---Create a new User from file
---@param name string username
---@return LocalUser|nil user Nil if user could not be loaded
function LocalUser.fromFile(name)
    if not fs.exists(name .. '.userDat') then
        return nil
    end
    local f = fsOpen(name .. '.userDat', 'r')
    if not f then
        osLog:error('Could not read userdata file for "' .. name..'"')
        return nil
    end
    local user = textutils.unserialise(f.readAll())
    f.close()
    if not user then
        osLog:error('Userdata file for "' .. name .. '" was coruppted')
        return nil
    end
    setmetatable(user, LocalUserMT)

    user._perm = {}
    for k, v in pairs(user.perm) do
        if type(k) == 'integer' then
            user._perm[v] = true
        elseif type(k) == 'string' then
            user._perm[k] = v
        end
    end
    user.perm = nil

    return user
end

---Save user to file
---@return boolean saved
function LocalUser:save()
    local f = fsOpen(self.name .. '.userDat', 'w')
    if not f then
        osLog:error('Could not save userdata file for "' .. self.name..'"')
        return false
    end
    f.write(textutils.serialise({
        name = self.name,
        pswH = self.pswH,
        perm = self._perm,
    }))
    f.close()
    osLog:info('Saved userdata file for "' .. self.name..'"')
    return true
end

---Check if user has permission node, or parent
---@param perm string permission node
---@return boolean hasPerm
function LocalUser:hasPerm(perm)
    if self._perm[perm] ~= nil then
        return self._perm[perm]
    end
    if perm:contains('.') then
        local parts = perm:split('.')
        for i = #parts, 1, -1 do
            local p = table.concat(parts, '.', 1, i) .. '.*'
            if self._perm[p] ~= nil then
                return self._perm[p]
            end
        end
    end
    if self._perm['*'] ~= nil then
        return self._perm['*']
    end
    return false
end

---Set permission node for server
---@param perm string permission node
---@param value boolean|nil permission status. true for has, false for block, nil to unset
---@return boolean saved If the change could be saved
function LocalUser:setPerm(perm, value)
    self._perm[perm] = value
    return self:save()
end

---Get user's home directory: <code>/home/username/</code>
---@return string homeDir
function LocalUser:getHomeDir()
    return '/home/' .. self.name .. '/'
end

---Check password
---@param pass string password to check
---@return boolean valid
function LocalUser:checkPass(pass)
    return self.pswH == sha256.hash(pass)
end
---Set the user's password
---@param oldPass string current password
---@param newPass string new password
---@return boolean set
function LocalUser:setPass(oldPass, newPass)
    if self.pswH == sha256.hash(oldPass) then
        self.pswH = sha256.hash(newPass)
        self:save()
        return true
    end
    return false
end

return LocalUser
