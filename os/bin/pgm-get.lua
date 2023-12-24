---@diagnostic disable
--local str = pos.require("strings")
--local tblStore = pos.require("tblStore")

local args = {...}

local manifestPathFile = "/os/pgm-get-manifest.json"
if not fs.exists(manifestPathFile) then
    local of = fs.open("/os/pgm-get-manifest.lua", "r")
    local nf = fs.open(manifestPathFile, "w")
    if of == nil or nf == nil then
        error("Failed to change from lua to json manifest", 0)
        return
    end
    nf.write(of.readAll())
    of.close()
    nf.close()
    -- manifestPathFile = manifestPathFile..".lua"
end

local function loadF(fileName, lua)
    -- lua = lua==nil or true
    local f = fs.open(fileName, "r")
    local tbl = {}
    if f == nil then
        error("Could not open "..fileName, 0)
        return nil
    end
    if lua then tbl = textutils.unserialise(f.readAll())
    else tbl = textutils.unserialiseJSON(f.readAll()) end
    f.close()
    return tbl
end
local function saveF(fileName, table, lua)
    local f = fs.open(fileName, "w")
    if f == nil then
        error("Could not open "..fileName, 0)
        return nil
    end
    if lua then f.write(textutils.serialise(table))
    else f.write(textutils.serialiseJSON(table)) end
    f.close()
    return true
end

local function getPrgmData(manifest, name)
    if manifest == nil then
        error("Manifest was nil", 0)
        return nil
    end
    for i=1,#manifest do
        if manifest[i].program == name then
            return manifest[i]
        end
    end
    return nil
end

local function version(manifest, name)
    for i=1,#manifest do
        if manifest[i].program == name then
            return manifest[i].version
        end
    end
    return -1
end

local function updateManifest()
    local resp, fMsg = http.get("https://peter.crall.family/minecraft/cc/pgm-get/manifest.json")
    if resp == nil then
        return false
    end

    if not(resp.getResponseCode() == 200) then
        return false
    end

    local f = fs.open(manifestPathFile, "w")
    f.write(resp.readAll())
    f.close()

    return true
end

local function install(pgm)
    -- local resp, fMsg = http.get("peter.crall.family/minecraft/cc/pgm-get/"..pgm..".lua")
    -- if fMsg == nil or resp == nil then
    --     return false
    -- end

    -- if not(resp.getResponseCode() == 200) then
    --     return false
    -- end

    local manifest = loadF(manifestPathFile, false)
    local prgmData = getPrgmData(manifest, pgm)

    if prgmData == nil then
        printError("Program data in manifest does not exist")
        return false
    end

    for i=1,#prgmData.files do
        local fN = prgmData.files[i]
        fN = pgm .."/".. fN
        local resp, fMsg = http.get("https://peter.crall.family/minecraft/cc/pgm-get/"..fN)
        if resp == nil then
            printError("HTTP error")
            return false
        end

        if not(resp.getResponseCode() == 200) then
            printError("HTTP error "..resp.getResponseCode())
            return false
        end
        local f = fs.open("/os/bin/"..fN, "w")
        f.write(resp.readAll())
        f.close()
    end

    shell.setAlias(prgmData.program, "/os/bin/"..prgmData.program.."/"..prgmData.exec)
    if prgmData.cmpt then
        if _G.pos then
            shell.setCompletionFunction("os/bin/"..prgmData.program.."/"..prgmData.exec, pos.require("os.bin."..prgmData.program.."."..prgmData.cmpt).complete)
        end
    end
    local pgmListData = {
        name = prgmData.program,
        exec = prgmData.exec,
        cmpt = prgmData.cmpt,
        startup = prgmData.startup,
        version = prgmData.version
    }

    local pgms = {}
    if fs.exists("/os/pgms.json") then
        pgms = loadF("/os/pgms.json", false)
    else
        pgms = loadF("/os/pgms.lua", true)
        saveF("/os/pgms.json", pgms, false)
        fs.delete("/os/pgms.lua")
    end
    local d = false
    for i=1,#pgms do
        if pgms[i].name == prgmData.program then
            pgms[i] = pgmListData
            d = true
        end
    end

    if not d then
        table.insert(pgms, pgmListData)
    end
    saveF("/os/pgms.json", pgms, false)

    -- local f = fs.open("/os/bin/"..pgm..".lua", "w")
    -- f.write(resp.readAll())
    -- f.close()
    -- shell.setAlias(pgm, "os/bin/"..pgm..".lua")

    -- return setAC(pgm)
    return true
end

local function upgrade(force)
    print("Checking manifest")

    local manifest = loadF(manifestPathFile, false)

    print("Ugrading programs ...")
    local pgms = {}
    if fs.exists("/os/pgms.json") then
        pgms = loadF("/os/pgms.json", false)
    else
        pgms = loadF("/os/pgms.lua", true)
    end

    local upg = false
    for i=1,#pgms do
        local pgm = pgms[i]

        if version(manifest, pgm.name) > pgm.version or (force and version(manifest, pgm.name) >= pgm.version) then
            print("Upgrading "..pgm.name)
            if not install(pgm.name) then
                print("Failed to upgrade "..pgm.name)
            else
                upg = true
            end
        end
    end
    if not upg then
        print("No programs were upgraded")
    end
    return
end

-- local function list()
--     local pgms = tblStore.loadF("/os/pgms.lua")
--     for i=1,#pgms do
--         print(pgms[i].name.." version "..pgms[i].version)
--     end
-- end

-- function setAC(pgm)
--     local resp, fMsg = http.get("peter.crall.family/minecraft/cc/pgm-get/"..pgm.."-complete.lua")
--     if fMsg == nil or resp == nil then
--         return false
--     end

--     if not(resp.getResponseCode() == 200) then
--         return false
--     end

--     local f = fs.open("/os/bin/"..pgm.."-conplete.lua", "w")
--     f.write(resp.readAll())
--     f.close()
    
--     shell.setCompletionFunction("/os/bin/"..pgm..".lua", require(".os.bin."..pgm.."-complete").complete)

--     return true
-- end

if #args == 1 then
    if args[1] == "update" then
        print("Updating manifest")
        if not updateManifest() then
            print("Failed to get manifest - Check connection and try again later")
        end
        
        return
    elseif args[1] == "upgrade" then
        upgrade(false)
        return
    end
elseif #args == 2 then
    if args[1] == "install" then
        local pgm = args[2]
        print("Checking manifest")
        if not updateManifest() then
            print("Failed to get manifest - Check connection and try again later")
            return
        end
        print("Installing "..pgm)
        if not install(pgm) then
            print("Failed to install "..pgm)
            return
        end
        print("Installed "..pgm)
        return
    elseif args[1] == "upgrade" then
        if args[2] == "force" then
            print("Forcing upgrade")
            upgrade(true)
            return
        else
            print("Only vaild second parameter for upgrade is 'force'")
        end
    end
end
print("Invalid Command: pgm-get <update|install> [program]")