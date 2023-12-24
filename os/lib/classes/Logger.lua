---@package pos

---@enum LoggerLevel Logging severity level
local LoggerLevel = {
    DEBUG = 5, --- Logs all messages
    INFO = 4, --- Logs all messages but debug
    WARN = 3, --- Logs all warning and error messages
    ERROR = 2, --- Logs error messages
    FATAL = 1, --- Logs only fatal error messages
    NONE = 0, --- Does not log messages
}
_G.pos.LoggerLevel = LoggerLevel

---@class Logger Basic to file logger
---@field path string Log file path (Read Only)
---@field private level LoggerLevel Log level (<code>DEBUG</code>-<code>NONE</code>)
---@field private file Handle|nil File write handle
---@field print boolean If the logger should also print to the shell
---@field logTime boolean If time should be included in the log
local Logger = {
    path = '/home/.pgmLog/',
    level = LoggerLevel.DEBUG,
    file = nil,
    print = false,
    logTime = false,
}

---Meta table for logger class
local LoggerMt = {
    __index = Logger
}

---Creates a new logger
---@constructor Logger
---@param path string Absolute path to log file OR file name in <code>/home/.pgmLog/</code>
---@param printToConsole boolean|nil If the logger should also print to the shell
---@return Logger logger
function _G.pos.Logger(path, printToConsole, copyOld)
    local o = {}
    setmetatable(o, LoggerMt)
    o:__init__(path, printToConsole, copyOld)
    return o
end

---Initializes the logger
---@param path string Absolute path to log file OR file name in <code>/home/.pgmLog/</code>
---@param printToConsole boolean|nil If the logger should also print to the shell
function Logger:__init__(path, printToConsole, copyOld)
    if not string.start(path, '/') then
        path = Logger.path .. path
    end
    self.path = path
    self.print = printToConsole or self.print
    if copyOld and fs.exists(path) then
        local oldPath = path:sub(1, #path - 4) .. '_old.log'
        if fs.exists(oldPath) then
            fs.delete(oldPath)
        end
        fs.copy(path, oldPath)
    end
    self.file = fs.open(path, 'w')
    -- self.errorFile = errorFile or false
end

---Checks if the file is currently open for writing
---@return boolean fileIsOpen
function Logger:fileIsOpen()
    return self.file ~= nil
end
---Sets the file path for new log messages
---@param path string Absolute path to log file OR file name in <code>/home/.pgmLog/</code>
function Logger:setPath(path)
    if not string.start(path, '/') then
        path = Logger.path .. path
    end
    if self.file then
        self.file.close()
    end
    self.path = path
    self.file = fs.open(path, 'w')
end

---Sets the logging severity level
---@param level LoggerLevel Logging severity level
function Logger:setLevel(level)
    self.level = level
end
---Gets the current logging severity level
---@return LoggerLevel level
function Logger:getLevel()
    return self.level
end

---Flushes the file. Called after every write
function Logger:flush()
    self.file.flush()
end
---Write a line to the log file
---@param str string Line to write, without trailing new line
function Logger:write(str)
    self.file.write(str .. '\n')
    self.file.flush()
    if self.print then
        print(str)
    end
end
---Write a error line to the log file
---@param str string Line to write, without trailing new line
function Logger:_writeError(str)
    self.file.write(str .. '\n')
    self.file.flush()
    if self._errorFile then
        self._errorFile.write(str .. '\n')
        self._errorFile.flush()
    end
    if self.print then
        printError(str)
    end
end

function Logger:getTimeString()
    if not self.logTime then
        return ''
    end
    local time = os.epoch('utc')
    local ms = time % 1000
    time = math.floor(time / 1000)
    local s = time % 60
    time = math.floor(time / 60)
    local m = time % 60
    time = math.floor(time / 60)
    local h = time % 24
    return h..':'..m..':'..s..'.'..ms..' | '
end

---Logs a <code>DEBUG</code> message
---@param message any Debug message
function Logger:debug(message)
    if self.level < 5 then return end
    self:write('DEBUG: ' .. self:getTimeString() .. tostring(message))
end

---Logs an <code>INFO</code> message
---@param message any Info message
function Logger:info(message)
    if self.level < 4 then return end
    self:write('INFO: ' .. self:getTimeString() .. tostring(message))
end

---Logs a <code>WARN</code> message
---@param message any Warning message
function Logger:warn(message)
    if self.level < 3 then return end
    self:write('WARN: ' .. self:getTimeString() .. tostring(message))
end

---Logs an <code>ERROR</code> message
---@param message any Error message
function Logger:error(message)
    if self.level < 2 then return end
    self:write('ERROR: ' .. self:getTimeString() .. tostring(message))
end

---Logs a <code>FATAL</code> message
---@param message any Fatal error message
function Logger:fatal(message)
    if self.level < 1 then return end
    self:write('FATAL: ' .. self:getTimeString() .. tostring(message))
end