local function fillDef(cfg, def)
    local bad = false
    for k, v in pairs(def) do
        if cfg[k] == nil then
            cfg[k] = v
            bad = true
            -- printError(k..' was missing')
        end
        if type(v) == 'table' then
            bad = bad or fillDef(cfg[k], v)
        end
    end
    return bad
end

local function loadConfig(path, default)
    if fs.exists(path) then
        local f = fs.open(path, 'r')
        if not f then
            printError('Could not access config file')
            return default
        end
        local cfg = textutils.unserialiseJSON(f.readAll())
        f.close()
        if fillDef(cfg, default) then
            printError('Config was missing parameters: '..path)
            f = fs.open(path, 'w')
            if not f then
                printError('Could not access config file')
            else
                f.write(textutils.serialiseJSON(cfg))
                f.close()
            end
        end
        return cfg
    else
        local f = fs.open(path, 'w')
        if not f then
            printError('Could not access config file')
            return default
        end
        f.write(textutils.serialiseJSON(default))
        f.close()
        return default
    end
end

return {
    fillDef = fillDef,
    loadConfig = loadConfig
}