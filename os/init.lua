local str = pos.require("strings")
local tblStore = pos.require("tblStore")

local f = fs.open("/os/pgms.json", "r")
-- local pgms = tblStore.loadF("/os/pgms.json")
if f == nil then
    error("Failed to load program file", 0)
    return
end
local pgms = textutils.unserialiseJSON(f.readAll())
f.close()

local classList = fs.list('/os/lib/classes/')
if classList then
    for _, file in pairs(classList) do
        if not fs.isDir('/os/lib/classes/' .. file) then
            shell.run('/os/lib/classes/' .. file)
        end
    end
end

shell.run("/os/net/init.lua")
shell.run("/os/gui/gui.lua")

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