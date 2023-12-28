local expect = require "cc.expect"

term.clear()
term.setCursorPos(1, 1)
print("Starting PeterOS")

---Package path for pos.require
_G.newPackagePath =
"/?;/?.lua;/?/init.lua;/os/?;/os/?.lua;/os/?/init.lua;/os/lib/?;/os/lib/?.lua;/os/lib/?/init.lua;/rom/modules/main/?;/rom/modules/main/?.lua;/rom/modules/main/?/init.lua"

---Set the package path to _G.newPackagePath
local function pathSet()
    package.path = newPackagePath
end

pathSet()
local _ = require("os.lib.string")
local str = require(".os.lib.strings")
local sha256 = require("hash.sha256")

local osFs = {
    open = fs.open,
    exists = fs.exists,
    isReadOnly = fs.isReadOnly,
    move = fs.move,
    copy = fs.copy,
    delete = fs.delete,
    makeDir = fs.makeDir,
    list = fs.list,
    isDir = fs.isDir
}

local appdataPath = "/home/.appdata"

local su = false

local version = ""

local Logger = require('os.lib.logger')
local log = Logger('log.log', false)
if not log then
    error('Could not open OS Log')
    return
end

-- local logF = fsOpen("log.log", "w")
-- logF.write("OS Log:\n")
-- logF.close()

if not fs.exists("/home") then
    fs.makeDir("/home")
end
if not fs.exists(appdataPath) then
    fs.makeDir(appdataPath)
end

-- local function log(msg)
--     local logF = fsOpen("log.log", "a")
--     logF.write(msg.."\n")
--     logF.close()
-- end

local function realizePathL(path, loc)
    expect(1, path, "string")
    expect(2, loc, "string")
    
    local adpS, adpE = path:find('%%appdata%%')
    if adpS then
        return appdataPath .. path:sub(adpE + 1)
    end
    
    if str.start(loc, "rom/") then
        if not str.start(path, "/") then path = "/" .. path end
        return path
    end
    -- print("Realizing path: "..loc..", "..path)
    -- path = path:gsub("%%appdata%%", appdataPath)
    -- log(path)
    if str.start(path, "/") then
        while str.start(path, "/") do
            path = string.sub(path, 2)
        end
        return "/" .. path
    end
    if loc == "" then
        if not str.start(path, "/") then path = "/" .. path end
        return path
    end
    local pA = str.split(path, "/")
    local lA = str.split(loc, "/")
    if lA[1] == "" then
        table.remove(lA, 1)
    end
    if pA[1] == "" then
        table.remove(pA, 1)
    end
    if pA[1] == lA[1] then
        if not str.start(path, "/") then path = "/" .. path end
        return path
    end

    for i = 1, #pA do
        if pA[i] == ".." then
            table.remove(lA)
        else
            table.insert(lA, pA[i])
        end
    end

    local rtn = ""
    for i = 1, #lA do
        rtn = rtn .. "/" .. lA[i]
    end
    return rtn
    -- return '/'..fs.combine(loc,path)
end
---Realize path relative to current program
---@param path string relative program
---@return string path Absolute path
local function realizePath(path)
    expect(1, path, "string")

    local pgm = shell.getRunningProgram()
    local loc = ""
    if not (pgm == nil) then
        loc = fs.getDir(pgm)
    end
    local tP = path
    return realizePathL(path, loc)
end

local function allowedFile(path)
    expect(1, path, "string")

    if su then return true end
    -- local pgm = shell.getRunningProgram()
    -- local loc = fs.getDir(pgm)
    -- local tP = path
    path = realizePath(path)
    -- log(pgm .. " | " .. loc .. ", " .. tP .. ", " .. path)
    if str.start(path, "startup.lua") then
        return false
    end
    if str.cont(path, ".userDat") then
        return false
    end
    if str.start(path, "/hw.addr") then
        return true
    end
    if str.start(path, "/home/") then
        return true
    end
    if str.start(path, "/disk") then
        return true
    end
    if str.start(path, "/mnt/") then
        return true
    end
    if path == "/os/pgm-get-manifest.lua" or path == "/os/pgms.lua" then
        return true
    end
    if str.start(path, "/os/bin/") then
        return true
    end
    return "r"
end

local function open(_path, mode)
    expect(1, _path, "string")
    expect(2, mode, "string")

    _path = realizePath(_path)
    local r = allowedFile(_path)
    if r == true then
        return osFs.open(_path, mode)
    elseif not (r == false) then
        if mode ~= "r" then
            printError("Could not open file for write, invalid Permissions")
        end
        return osFs.open(_path, r)
    else
        printError("Could not open file, invalid Permissions")
        return nil
    end
end

local function exists(_path)
    expect(1, _path, "string")

    -- _path = _path:gsub("%%appdata", "/home/.appdata")
    local adpS, adpE = _path:find('%%appdata%%')
    if adpS then
        _path =  appdataPath .. _path:sub(adpE+1)
    end
    return osFs.exists(_path)
    -- r = allowedFile(_path)
    -- if r==false then return false
    -- else return fsExists(_path)
    -- end
end

local function isReadOnly(_path)
    expect(1, _path, "string")

    _path = realizePath(_path)
    local r = allowedFile(_path)
    if r == true then
        return osFs.isReadOnly(_path)
    else
        return true
    end
end

local function move(_src, _dest)
    expect(1, _src, "string")
    expect(2, _dest, "string")

    _src = realizePath(_src)
    _dest = realizePath(_dest)
    local rS = allowedFile(_src)
    local rD = allowedFile(_dest)
    if rS == true and rD == true then
        osFs.move(_src, _dest)
    else
        printError("Could not move file, invalid Permissions")
    end
end

local function copy(_src, _dest)
    expect(1, _src, "string")
    expect(2, _dest, "string")

    _src = realizePath(_src)
    _dest = realizePath(_dest)
    local rS = allowedFile(_src)
    local rD = allowedFile(_dest)
    if (rS == true or rS == "r") and rD == true then
        osFs.copy(_src, _dest)
    else
        printError("Could not copy file, invalid Permissions")
    end
end

local function delete(_path)
    expect(1, _path, "string")

    _path = realizePath(_path)
    if allowedFile(_path) == true then
        osFs.delete(_path)
        return true
    end
    printError("Could not delete file, invalid Permissions")
    return false
end

local function makeDir(_path)
    expect(1, _path, "string")

    _path = realizePath(_path)
    if allowedFile(_path) == true then
        osFs.makeDir(_path)
        return true
    end
    printError("Could not create directory, invalid Permissions")
    return false
end

local function list(_path)
    _path = realizePath(_path)
    return osFs.list(_path)
end

local function isDir(_path)
    _path = realizePath(_path)
    return osFs.isDir(_path)
end

local users = {}

local LocalUser = loadfile('/os/user/LocalUser.lua')(osFs.open, log, require)

local function getUserData(user)
    expect(1, user, "string")

    if users[user] then
        return users[user]
    end

    local u = LocalUser.fromFile(user)
    if not u then
        return nil
    end
    users[user] = u
    return u

    -- local f = fsOpen("/" .. user .. ".userDat", "r")
    -- if not f then
    --     log:error('Could not read user data from '..user)
    --     return {
    --         name=user,
    --         pswH='',
    --         perm={"*"}
    --     }
    -- end
    -- local dta = f.readAll()
    -- f.close()
    -- if str.start(dta, "{") then
    --     local data = textutils.unserialise(dta)
    --     return data
    -- end
    -- return {
    --     name=user,
    --     pswH=dta,
    --     perm={"*"}
    -- }
end

---Set user as super user
---@param psw string Password
---@return boolean isSu If the password was correct
local function sudo(psw)
    expect(1, psw, "string")

    -- local hs = sha256.hash(psw)
    -- local f = fsOpen("/su.userDat", "r")
    local suUsrDat = getUserData("su")
    if not suUsrDat then
        log:error('Could not get su data')
        return false
    end
    su = suUsrDat:checkPass(psw)
    return su
    -- local sPsw = f.readAll()
    -- f.close()
    -- if hs == suUsrDat.pswH then su = true
    -- else su = false
    -- end
    -- return su
end

---Check if the current user is the super user
---@return boolean isSu Is super user
local function isSu()
    return su
end

---Gets the current POS version
---@return string version POS version
local function getVersion()
    if version ~= "" then
        return version
    end
    local vf = fs.open("/version.txt", "r")
    if not vf then
        return 'Unknown'
    end
    version = vf.readLine()
    vf.close()
    return version
end

---Set the super user password
---@param cPass string Current password
---@param nPass string New Password
---@return boolean set If the password was changed
local function setSuPass(cPass, nPass)
    expect(1, cPass, "string")
    expect(2, nPass, "string")

    -- local hs = sha256.hash(cPass)
    -- local f = fsOpen("/su.userDat", "r")
    -- local sPsw = f.readAll()
    local suUsrDat = getUserData("su")
    if not suUsrDat then
        log:error('Could not get su data')
        return false
    end
    return suUsrDat:setPass(cPass, nPass)
    -- f.close()
    -- if not hs==suUsrDat.pswH then
    --     printError("Invalid password")
    --     return false
    -- end
    -- local nh = sha256.hash(nPass)
    -- suUsrDat.pswH = nh
    -- setUserData("su", suUsrDat)
    -- f = fsOpen("/su.userDat", "w")
    -- f.write(nh)
    -- f.close()
    -- return true
end

local cUser = nil

local function hasPerm(perm)
    if su then
        return true
    end
    if cUser == nil then
        return false
    end
    return cUser:hasPerm(perm)
end

local function changeUser(name, pass)
    if name == '' then
        cUser = nil
    end
    local u = getUserData(name)
    if not u then
        return false
    end
    if u:checkPass(pass) then
        cUser = u
        return true
    end
    return false
end

local function getUser()
    if not cUser then
        return nil
    end
    return cUser.name
end

_G.user = {
    isSu = isSu,
    sudo = sudo,
    setSuPass = setSuPass,
    hasPerm = hasPerm,
    changeUser = changeUser,
    getUser = getUser
}

_G.pos = {
    pathSet = pathSet,
    version = getVersion,
    realizePath = realizePath,
    relizePath = realizePath,
    log = log
}

fs.open = open
fs.exists = exists
fs.isReadOnly = isReadOnly
fs.move = move
fs.copy = copy
fs.delete = delete
fs.makeDir = makeDir
fs.list = list
fs.isDir = isDir

---@class EventHandler
---@field handler function Handler function, takes event table
---@field filter nil|string[] Event filter, leave `nil` to handle all events
local EventHandler = {}
function EventHandler:try(eType, event)
    if self.filter == nil then
        self.handler(event)
    else
        for _,filter in pairs(self.filter) do
            if filter == eType then
                self.handler(event)
                return
            end
        end
    end
end

local eventHandlers = {} ---@type table<number, EventHandler>
local eventHandlerId = 0

---Add an event handler
---@param handler function Event handler function, takes event table
---@param filter nil|string|string[] Event type filter. Leave `nil` for all events
---@return integer handlerId Event handler Id, used to remove handler
function pos.addEventHandler(handler, filter)
    expect(1, handler, "function")
    expect(2, filter, "nil", 'string', 'table')
    if type(filter) == 'string' then
        filter = { filter }
    end
    local ehId = eventHandlerId
    eventHandlerId = eventHandlerId + 1
    local eventHandler = {
        handler = handler,
        filter = filter
    }
    eventHandlers[ehId] = eventHandler
    return ehId
end
---Remove an event handler by ID
---@param handlerId number Event handler Id returned by `pos.addEventHandler()`
---@return number handlerId Id of event handler that was removed
function pos.removeEventHandler(handlerId)
    eventHandlers[handlerId] = nil
    return handlerId
end

local osPullEventRaw = os.pullEventRaw
local function pullEventRaw(sFilter)
    while true do
        local event = { osPullEventRaw() }
        local eType = event[1]

        for _, eHandler in pairs(eventHandlers) do
            eHandler:try(eType, event)
        end
        
        if not sFilter or sFilter == eType then
            return unpack(event)
        end
    end
end
os.pullEventRaw = pullEventRaw

os.pullEvent = function(sFilter)
    local event = { os.pullEventRaw(sFilter) }
    if event[1] == "terminate" then
        error("Terminating", 0)
    end
    return unpack(event)
end

-- local requireO = require
-- local logF = fsOpen("thing.log", "w")
-- logF.write("");
-- logF.close()
-- function requireN(path)
--     local logF = fsOpen("thing.log", "a")
--     logF.write("\n")
--     logF.write(path.."\n")
--     logF.write(package.path.."\n")
--     logF.close()
--     return requireO(path)
-- end

-- require = requireN

---Require function.
---Works to require pos packages from /os/ and /os/lib/
---@param path string package name and path
---@return table package
---@diagnostic disable-next-line: duplicate-set-field
_G.pos.require = function(path)
    expect(1, path, "string")

    local pP = package.path
    package.path = newPackagePath
    local api = require(path)
    package.path = pP
    return api
end
-- net.setup()

if not _G.pgm then
    _G.pgm = {}
end

shell.run("/os/init.lua")
if (_G.pgmGet) then pgmGet.init(osFs.open)
else printError('Could not start pgm-get, consider updating it with pgm-get install pgm-get')
end
print("Finished Loading " .. getVersion())
local lbl = os.getComputerLabel()
if not (lbl == nil) then
    print("")
    print(lbl)
end

local vRsp, vMsg = http.get("https://raw.githubusercontent.com/Platratio34/peterOS/master/version.txt")

if vRsp == nil then
    log:error("HTTP error: "..vMsg)
elseif vRsp.getResponseCode() ~= 200 then
    printError("HTTP response code " .. vRsp.getResponseCode() .. " msg: " .. vRsp.readAll())
else
    local lVersion = vRsp.readAll()
    if getVersion() ~= lVersion then
        print('')
        print('OS is out of date, latest version ' .. lVersion)
        print('Use `osUpdate` to update to latest')
    end
end

if fs.exists("/disk/installer.lua") then
    print("")
    print("Run 'diskInstall' to install content from disk")
    print("Use 'sudo' or 'su' if it is OS installer")
    shell.setAlias("diskInstall", "/disk/installer.lua")
    if fs.exists("/disk/installer-complete.lua") then
        shell.setCompletionFunction("disk/installer.lua", require(".disk.installer-complete").complete)
    end
    print("")
end
if fs.exists("/disk/diskInstaller/installer.lua") then
    print("")
    print("Run 'diskInstall' to install content from disk")
    print("Use 'sudo' or 'su' if it is OS installer")
    shell.setAlias("diskInstall", "/disk/diskInstaller/installer.lua")
    if fs.exists("/disk/diskInstaller/installer-complete.lua") then
        shell.setCompletionFunction("disk/diskInstaller.installer.lua",
            require(".disk.diskInstaller.installer-complete").complete)
    end
    print("")
end

shell.setDir("/home/")

if fs.exists("/home/startup") then
    print("Running custom startups ...")
    print("")
    local startupFiles = fs.list("/home/startup/")
    if not startupFiles then
        log:error('Could not get startup files, skipping them')
        return
    end

    for i = 1, #startupFiles do
        local f = startupFiles[i]
        if (str.cont(f, ".lua")) then
            shell.run("/home/startup/" .. f)
        end
    end
end
