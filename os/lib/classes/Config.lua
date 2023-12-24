---@package pos

---@class Config Config access class
---@field path string Path to normal config file
---@field data table Config data
---@field default table Default config data
---@field loaded boolean If the config has been loaded from file
local Config = {
    path = '',
    data = {},
    default = {},
    loaded = false,
    existed = false,
}

---Creates a config object
---@constructor Config
---@param path string Path to config file
---@param default table|nil Optional. Default config values
---@param createDef boolean|nil Optional. If the file does not exist, create default config
---@return Config config
function pos.Config(path, default, createDef)
    local o = {}
    setmetatable(o, { __index = Config })
    o:__init__(path, default or {}, createDef or false)
    return o
end

---Initilize the config object
---@param path string Path to config file
---@param default table Default config values
---@param createDef boolean Optional. If the file does not exist, create default config
function Config:__init__(path, default, createDef)
    self.path = path
    self.default = default
    if createDef then self:loadOrDef()
    else self:load()
    end
end

---Load the config from file
---@param path nil|string Optional. Temporary path to load config from
---@return boolean loaded
function Config:load(path)
    self.loaded = false
    path = path or self.path
    local f = fs.open(path, 'r')
    if not f then
        return false
    end
    local data = textutils.unserialiseJSON(f.readAll())
    f.close()
    if not data then
        return false
    end
    self.data = data
    setmetatable(data, { __index = self.default })
    self.loaded = true
    return true
end

---Load the config from file, or create a default one at the path
---@param path nil|string Optional. Temporary path to load config from
---@return boolean loaded
function Config:loadOrDef(path)
    path = path or self.path
    self.loaded = false
    if fs.exists(path) then
        self:load(path)
    else
        if not self:saveAll(path) then
            return false
        end
        self:load(path)
    end
    return true
end

---Saves the config to file
---@param path nil|string Optional. Temporary path to save config to
---@return boolean saved
function Config:save(path)
    path = path or self.path
    local f = fs.open(path, 'w')
    if not f then
        return false
    end
    local t = {}
    for k, v in pairs(self.data) do
        if k ~= '__metatable' then t[k] = v end
    end
    f.write(textutils.serialiseJSON(t))
    f.close()
    return true
end

---Saves the config, including default values, to file
---@param path nil|string Optional. Temporary path to save config to
---@return boolean saved
function Config:saveAll(path)
    path = path or self.path
    local f = fs.open(path, 'w')
    if not f then
        return false
    end
    local t = {}
    for k, v in pairs(self.data) do
        if k ~= '__metatable' then t[k] = v end
    end
    for k, v in pairs(self.default) do
        t[k] = t[k] or v
    end
    f.write(textutils.serialiseJSON(t))
    f.close()
    return true
end