---Parameter type expect
---@param aI integer
---@param val any
---@param ... string
function _G.expect(aI, val, ...)
    local aType = type(val)
    if aType == 'table' then
        if getmetatable(val) and getmetatable(val).type then
            aType = getmetatable(val).type
        end
    end
    local reqTypes = { ... }
    if #reqTypes == 1 then
        if aType ~= reqTypes[1] then
            error(('Argument %s must be a %s, was %s'):format(aI, reqTypes[1], aType), 3)
        end
    end
    local typesString = ''
    for i = 1, #reqTypes do
        if aType == reqTypes[i] then
            return
        else
            if #typesString > 0 then
                typesString = typesString .. ', '
            end
            typesString = typesString .. reqTypes[i]
        end
    end
    error(('Argument %s must be one of %s, was %s'):format(aI, typesString, aType), 3)
end

shell.run("/os/net/init.lua")
shell.run("/os/gui/gui.lua")

local fo = fs.open("/os/osPgms.json", "r")
if fo == nil then
    error("Failed to load program file", 0)
    return
end
local osPgms = textutils.unserialiseJSON(fo.readAll())
fo.close()

for i = 1, #osPgms do
    local pgm = osPgms[i]
    local dirPath = "os/bin/"
    local modPath = "os.bin."
    if fs.isDir("/" .. dirPath .. pgm.name) then
        dirPath = dirPath .. pgm.name .. "/"
        modPath = modPath .. pgm.name .. "."
    end
    shell.setAlias(pgm.name, "/" .. dirPath .. pgm.exec)
    if pgm.cmpt then
        local completer = pos.require(modPath .. pgm.cmpt).complete
        shell.setCompletionFunction(dirPath .. pgm.exec, completer)
    end
    if pgm.startup ~= nil then
        -- print("Running startup for "..pgm.name)
        if type(pgm.startup) == 'table' then
            for _, file in pairs(pgm.startup) do
                shell.run("/" .. dirPath .. file)
            end
        else
            shell.run("/" .. dirPath .. pgm.startup)
        end
    end
    -- print("Loaded program "..pgm.name)
end

local f = fs.open("/os/pgms.json", "r")
if f == nil then
    error("Failed to load program file", 0)
    return
end
local pgms = textutils.unserialiseJSON(f.readAll())
f.close()

for i = 1, #pgms do
    local pgm = pgms[i]
    local dirPath = "os/bin/"
    local modPath = "os.bin."
    if fs.isDir("/" .. dirPath .. pgm.name) then
        dirPath = dirPath .. pgm.name .. "/"
        modPath = modPath .. pgm.name .. "."
    end
    shell.setAlias(pgm.name, "/" .. dirPath .. pgm.exec)
    if pgm.cmpt then
        local completer = pos.require(modPath .. pgm.cmpt).complete
        shell.setCompletionFunction(dirPath .. pgm.exec, completer)
    end
    if pgm.startup ~= nil then
        -- print("Running startup for "..pgm.name)
        if type(pgm.startup) == 'table' then
            for _, file in pairs(pgm.startup) do
                shell.run("/" .. dirPath .. file)
            end
        else
            shell.run("/" .. dirPath .. pgm.startup)
        end
    end
    -- print("Loaded program "..pgm.name)
end