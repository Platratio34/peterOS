local expect = require "cc.expect"

term.clear()
term.setCursorPos(1, 1)
print("Starting PeterOS")

---Package path for pos.require
_G.newPackagePath =
"/?;/?.lua;/?/init.lua;/os/?;/os/?.lua;/os/?/init.lua;/os/lib/?;/os/lib/?.lua;/os/lib/?/init.lua;/rom/modules/main/?;/rom/modules/main/?.lua;/rom/modules/main/?/init.lua"

_G.user = {} ---PeterOS user module
_G.pos = {} ---PeterOS OS module

---Set the package path to _G.newPackagePath
function pos.pathSet()
    package.path = newPackagePath
end

pos.pathSet()
local _ = require("os.lib.string")

local classList = fs.list('/os/lib/classes/')
if type(classList) == 'table' then
    for _, file in pairs(classList) do
        if not fs.isDir('/os/lib/classes/' .. file) then
            shell.run('/os/lib/classes/' .. file)
        end
    end
else
    error("Could not load OS classes; Could not get list")
    return
end

local internal = {
    blockTerminate = false
}

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
internal.fs = osFs

local appdataPath = "/home/.appdata"

local su = false

local version = ""
local versionId = ""

---OS Log
local log = pos.Logger('/pos.log', false, true)
pos.log = log ---OS log
internal.log = log
if not log then
    error('Could not open OS Log')
    return
end

if not fs.exists("/home") then
    fs.makeDir("/home")
end
if not fs.exists(appdataPath) then
    fs.makeDir(appdataPath)
end

---Instance a given class
---@param class table Class table
---@param ... any constructor arguments
---@return table instance
function pos.instanceClass(class, ...)
    local o = {}
    setmetatable(o, {__index = class})
    if (o.__init__) then
        o:__init__(...)
    end
    return o
end

---Realize full path from relative path and execution location
---@param path string
---@param loc string
---@return string fullPath
local function realizePathL(path, loc)
    expect(1, path, "string")
    expect(2, loc, "string")
    
    local adpS, adpE = path:find('%%appdata%%')
    if adpS then
        return appdataPath .. path:sub(adpE + 1)
    end
    
    if loc:start("rom/") then
        if not path:start("/") then path = "/" .. path end
        return path
    end
    if path:start("/") then
        while path:start("/") do
            path = string.sub(path, 2)
        end
        return "/" .. path
    end
    if loc == "" then
        if not path:start("/") then path = "/" .. path end
        return path
    end
    local pA = path:split("/")
    local lA = loc:split("/")
    if lA[1] == "" then
        table.remove(lA, 1)
    end
    if pA[1] == "" then
        table.remove(pA, 1)
    end
    if pA[1] == lA[1] then
        if not path:start("/") then path = "/" .. path end
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
end
---Realize path relative to current program
---@param path string relative program
---@return string path Absolute path
function pos.realizePath(path)
    expect(1, path, "string")

    local pgm = shell.getRunningProgram()
    local loc = ""
    if not (pgm == nil) then
        loc = fs.getDir(pgm)
    end
    local tP = path
    return realizePathL(path, loc)
end
pos.relizePath = pos.realizePath

---Check if a file should be read or writeable
---@param path string file path
---@return boolean|"r" allowed if the file should be accessible, or read only
local function allowedFile(path)
    expect(1, path, "string")

    if su then return true end
    path = pos.realizePath(path)
    -- log(pgm .. " | " .. loc .. ", " .. tP .. ", " .. path)
    if path:start("startup.lua") then
        return false
    elseif path:cont(".userDat") then
        return false
    elseif path:start("/hw.addr") then
        return true
    elseif path:start("/home/") then
        return true
    elseif path:start("/disk") then
        return true
    elseif path:start("/mnt/") then
        return true
    elseif path == "/os/pgm-get-manifest.lua" or path == "/os/pgms.lua" then
        return true
    elseif path:start("/os/bin/") then
        return true
    end
    return "r"
end

local function open(_path, mode)
    expect(1, _path, "string")
    expect(2, mode, "string")

    _path =pos.realizePath(_path)
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
fs.open = open

local function exists(_path)
    expect(1, _path, "string")

    local adpS, adpE = _path:find('%%appdata%%')
    if adpS then
        _path =  appdataPath .. _path:sub(adpE+1)
    end
    return osFs.exists(_path)
end
fs.exists = exists

local function isReadOnly(_path)
    expect(1, _path, "string")

    _path = pos.realizePath(_path)
    local r = allowedFile(_path)
    if r == true then
        return osFs.isReadOnly(_path)
    else
        return true
    end
end
fs.isReadOnly = isReadOnly

local function move(_src, _dest)
    expect(1, _src, "string")
    expect(2, _dest, "string")

    _src = pos.realizePath(_src)
    _dest = pos.realizePath(_dest)
    local rS = allowedFile(_src)
    local rD = allowedFile(_dest)
    if rS == true and rD == true then
        osFs.move(_src, _dest)
    else
        printError("Could not move file, invalid Permissions")
    end
end
fs.move = move

local function copy(_src, _dest)
    expect(1, _src, "string")
    expect(2, _dest, "string")

    _src = pos.realizePath(_src)
    _dest = pos.realizePath(_dest)
    local rS = allowedFile(_src)
    local rD = allowedFile(_dest)
    if (rS == true or rS == "r") and rD == true then
        osFs.copy(_src, _dest)
    else
        printError("Could not copy file, invalid Permissions")
    end
end
fs.copy = copy

local function delete(_path)
    expect(1, _path, "string")

    _path = pos.realizePath(_path)
    if allowedFile(_path) == true then
        osFs.delete(_path)
        return true
    end
    printError("Could not delete file, invalid Permissions")
    return false
end
fs.delete = delete

local function makeDir(_path)
    expect(1, _path, "string")

    _path = pos.realizePath(_path)
    if allowedFile(_path) == true then
        osFs.makeDir(_path)
        return true
    end
    printError("Could not create directory, invalid Permissions")
    return false
end
fs.makeDir = makeDir

local function list(_path)
    _path = pos.realizePath(_path)
    return osFs.list(_path)
end
fs.list = list

local function isDir(_path)
    _path = pos.realizePath(_path)
    return osFs.isDir(_path)
end
fs.isDir = isDir

local users = {}

local LocalUser = loadfile('/os/user/LocalUser.lua')(osFs.open, log, require)

---Get user data by username
---@param user string Username
---@return LocalUser? user
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
end

---Set user as super user
---@param psw string Password
---@return boolean isSu If the password was correct
function user.sudo(psw)
    expect(1, psw, "string")
    
    local suUsrDat = getUserData("su")
    if not suUsrDat then
        log:error('Could not get su data')
        return false
    end
    su = suUsrDat:checkPass(psw)
    return su
end

---Check if the current user is the super user
---@return boolean isSu Is super user
function user.isSu()
    return su
end

---Gets the current POS version
---@return string version POS version
function pos.version()
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

---Get the current POS version ID (`vX.X` or `vX.X-dev`)
---@return string versionId
function pos.versionId()
    if versionId ~= "" then
        return versionId
    end
    local v = pos.version()
    local s, e = v:find('V%d+%.%d+%-?[Dd]?e?v?')
    if s == nil then return "" end
    versionId = v:sub(s, e):lower()
    return versionId
end

---Set the super user password
---@param cPass string Current password
---@param nPass string New Password
---@return boolean set If the password was changed
function user.setSuPass(cPass, nPass)
    expect(1, cPass, "string")
    expect(2, nPass, "string")
    
    local suUsrDat = getUserData("su")
    if not suUsrDat then
        log:error('Could not get su data')
        return false
    end
    return suUsrDat:setPass(cPass, nPass)
end

local cUser = nil

---Check if the current user has the specified permission
---@param perm string Permission to check for
---@return boolean has
function user.hasPerm(perm)
    if su then
        return true
    end
    if cUser == nil then
        return false
    end
    return cUser:hasPerm(perm)
end

---Change the current user
---@param name string New username
---@param pass string New user password
---@return boolean changed
function user.changeUser(name, pass)
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

---Get the current user name. **DOES NOT GET SUPER USER**
---@return string user
function user.getUser()
    if su then
        return "super"
    end
    if not cUser then
        return ""
    end
    return cUser.name
end

---Make a new local user on the system. **REQUIRES SUPER USER**
---@param name string
---@param pass string
---@return boolean userCreated
function user.newUser(name, pass)
    if not user.isSu() then
        log:warn('Tried to make a new user, but was not super user')
        return false
    end
    if fs.exists('/' .. name .. '.userDat') then
        log:warn('Tried to make a new user, user `%s` already existed', name)
        return false
    end
    local user = LocalUser(name, pass, {}) ---@type LocalUser
    user:save()
    log:info('User `%s` created')
    return true
end

local osEvents = loadfile("/os/events.lua")(log, require, internal)

---Require function.
---Works to require pos packages from /os/ and /os/lib/
---@param path string package name and path
---@return table package
pos.require = function(path)
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
print("Finished Loading " .. pos.version())
local lbl = os.getComputerLabel()
if not (lbl == nil) then
    print("")
    print(lbl)
end

local requireLogin = false
if fs.exists('/user.cfg') then
    local f = fs.open('/user.cfg')
    local userCfg = textutils.unserialiseJSON(f.readAll())
    f.close()
    if userCfg.requireLogin then
        requireLogin = true
        internal.blockTerminate = true
    end
end

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
        if (f:cont(".lua")) then
            shell.run("/home/startup/" .. f)
        end
    end
end

while requireLogin do
    print('')
    write('Enter user name: ')
    local username = read()
    print()
    write('Password for ' .. username .. ': ')
    local password = read('')
    local u = getUserData(username)
    if not u then
        return false
    elseif u:checkPass(password) then
        requireLogin = false
        log:info('User %s logged in', username)
    else
        log:warn('Failed login for user %s', username)
        term.setTextColor(colors.red)
        print('Invalid user or password')
        term.setTextColor(colors.white)
    end
end

local vRsp, vMsg = http.get("https://raw.githubusercontent.com/Platratio34/peterOS/master/version.txt")

if vRsp == nil then
    log:error("HTTP error: "..vMsg)
elseif vRsp.getResponseCode() ~= 200 then
    printError("HTTP response code " .. vRsp.getResponseCode() .. " msg: " .. vRsp.readAll())
else
    local lVersion = vRsp.readAll()
    if pos.version() ~= lVersion then
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
