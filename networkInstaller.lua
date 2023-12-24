-- wget run https://raw.githubusercontent.com/Platratio34/peterOS/master/networkInstaller.lua

local args = {...}

local function cont(_str1, _str2)
    return not(string.find(_str1,_str2)==nil)
end

local over = 0
if (args[1] == 'y') then
    over = 1
end

if fs.exists("/os") then
    print("OS already installed")
    if over == 0 then
        write("Do you want to overwrite it? (y/n) ") 
        local i = string.lower(read())
        if i=="y" then 
            over = 1
            shell.run("su")
        end
    end
    if over == 1 then
        -- print("Erasing OS Files . . .")
        -- fs.delete("/os/")
        -- fs.delete("/startup.lua") 
    else
        print("Terminating install")
        return
    end
end

local repoURL = 'https://raw.githubusercontent.com/Platratio34/peterOS/'
local newVersion = 'master'
for i,arg in pairs(args) do
    if arg == '-v' then
        if #args < i + 1 then
            printError('Must specify version after -v')
            return
        end
        newVersion = args[i + 1]
    end
end
local baseURL = repoURL .. newVersion .. '/'

print('Pulling manifest for version '..newVersion)

local rsp, msg = http.get(baseURL.."install-manifest.json")

if rsp == nil then
    printError("HTTP error: "..msg)
    return
end
if rsp.getResponseCode() ~= 200 then
    printError("HTTP response code " .. rsp.getResponseCode() .. " msg: " .. rsp.readAll())
    return
end

local fileManifest = textutils.unserialiseJSON(rsp.readAll())
if fileManifest == nil then
    printError("Failed to unserialise install manifest")
    return
end

local function writeToFile(path, text)
    local f = fs.open(path, 'w')
    if not f then return false end
    f.write(text)
    f.close()
    return true
end
local function readFromFile(path)
    local f = fs.open(path, 'r')
    if not f then return '' end
    local t = f.readAll()
    f.close()
    return t
end

local pgms = nil
if fs.exists("/os/pgms.lua") then
    print("Backing up program list")
    -- local f = fs.open("/os/pgms.lua", "r")
    -- pgms = textutils.unserialise(f.readAll())
    -- f.close()
    pgms = textutils.unserialise(readFromFile("/os/pgms.lua"))
    fs.delete("/os/pgms.lua")
end
if fs.exists("/os/pgms.json") then
    print("Backing up program list")
    local f = fs.open("/os/pgms.json", "r")
    if f ~= nil then
        pgms = textutils.unserialiseJSON(f.readAll())
        f.close()
    end
end

print("Downloading OS files")
for i=1,#fileManifest.files do
    local fileName = fileManifest.files[i]
    local fileRsp, error = http.get(baseURL..fileName)

    if fileRsp == nil then
        printError(fileName .." | HTTP error: "..error)
        print("Terminating install")
        return
    end
    if fileRsp.getResponseCode() ~= 200 then
        printError(fileName .." | HTTP response code " .. fileRsp.getResponseCode() .. " msg: " .. fileRsp.readAll())
        print("Terminating install")
        return
    end

    local percent = math.floor((i/#fileManifest.files)*100)
    if fileName == ".settings" then
        if not fs.exists("/.settings") then
            print(percent.."% | Creating .settings")
            -- local f = fs.open("/.settings", "w")
            -- f.write(fileRsp.readAll())
            -- f.close()
            writeToFile("/.settings", fileRsp.readAll())
            -- fs.copy("/disk/.settings", "/.settings")
        else
            print(percent.."% | Modifying .settings")
            local df = fs.open("/.settings", "r")
            df = df or {}
            df.readLine()
            fileRsp.readLine()
            local lines = {}
            local line = df.readLine()
            while not(cont(line, "}")) do
                table.insert(lines, line)
                line = df.readLine()
            end
            while not(cont(line,"}")) do
                table.insert(lines, line)
                line = fileRsp.readLine()
            end
            df.close()
            local of = fs.open("/.settings", "w")
            of = of or {}
            of.writeLine("{")
            for j=1,#lines do
                of.writeLine(lines[j])
            end
            of.writeLine("}")
            of.close()
        end
    elseif fileName == "su.userDat" then
        if fs.exists("su.userDat") then
            print(percent.."% | Skipping su.userDat, already exists")
        else
            -- local f = fs.open("/"..fileName, "w")
            -- f.write(fileRsp.readAll())
            -- f.close()
            writeToFile("/"..fileName, fileRsp.readAll())
            print(percent.."% | Downloaded " .. fileName)
        end
    else
        -- local f = fs.open("/"..fileName, "w")
        -- f.write(fileRsp.readAll())
        -- f.close()
        writeToFile("/"..fileName, fileRsp.readAll())
        print(percent.."% | Downloaded " .. fileName)
    end
end
print("Done downloading OS")

print("Installing pgm-get")

local rspPGCore, msgPGCore = http.get('https://raw.githubusercontent.com/peterOS-pgm-get/pgm-get/master/core.lua')

if rspPGCore == nil then
    printError("HTTP error getting pgm-get: " .. msgPGCore)
    return
end
if rspPGCore.getResponseCode() ~= 200 then
    printError("HTTP response code " .. rspPGCore.getResponseCode() .. " getting pgm-get; msg: " .. rspPGCore.readAll())
    return
end
local pgCoreF = fs.open('/os/bin/pgm-get/core.lua', 'w')
if not pgCoreF then
    printError('Unable to install pgm-get')
    return
end
pgCoreF.write(msgPGCore.readAll())
pgCoreF.close()
shell.run('/os/bin/pgm-get/core.lua')

print("Installing default programs")
pgmGet.updateManifest()
for i=1,#fileManifest.pgms do
    local program = fileManifest.pgms[i]
    local percent = math.floor((i/#fileManifest.pgms)*100)
    print(percent.."% | Installing "..program)
    -- shell.run("/os/bin/pgm-get", "install", program)
    pgmGet.install(program, 'latest', true)
end
print("Done installing default programs")

if not (pgms == nil) then
    print("Installing previous programs")
    -- pgmGet.upgrade(true)
    for _,pgm in pairs(pgms) do
        if pgm.forcedVersion then
            pgmGet.install(pgm.name, pgm.version, true)
        else
            pgmGet.install(pgm.name, 'latest', true)
        end
    end

    print("Done installing previous programs")
end

if os.getComputerLabel() == nil then
    term.write("Computer name: ")
    os.setComputerLabel(read())
end

print("")
print("OS downloaded, ready for reboot")
print("")

print("Press enter to reboot")
read()
print("Rebooting . . .")
os.reboot()