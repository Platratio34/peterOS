---@class Lock A lockout handler
---@field private __state boolean
---@field package _message any
---@field private __callbacks fun(msg: any?)[]
local Lock = {}

local LockMT = {
    __index = Lock
}

---Create a new lock. Does not activate it
---@return Lock
function pos.Lock()
    local o = {}
    setmetatable(o, LockMT)
    o.__init__()
    return o
end

function Lock:__init__()
    self.__state = false
    self._message = nil
    self.__callbacks = {}
end

---Activates the lock
---@return Lock self
function Lock:lock()
    self.__state = true
    self._message = nil
    return self
end

---Release the lock, trigger the callback, and letting watchers continue
---@param message any? Release message. Provided to callbacks and returned from `await`
function Lock:release(message)
    self.__state = false
    self._message = message
    for _, fun in ipairs(self.__callbacks) do
        fun()
    end
end

---Await the release of the lock.
---@param timeout number? Timeout (in seconds) to wait before breaking early
---@param step number? Step side (in seconds) to check for release
---@return boolean
---@return any
---@see Lock.onRelease for asynchronous actions
function Lock:await(timeout, step)
    step = step or 0.1
    local time = 0
    while self.__state do
        sleep(step)
        time = time + step
        if timeout and time > timeout then
            return false
        end
    end
    return true, self._message
end

---Add an on release callback that takes the message if provided
---@param callback fun(msg: any?):nil Callback function to add
function Lock:onRelease(callback)
    self.__callbacks[callback] = callback
end

---Remove an on release callback
---@param callback fun(msg: any?):nil Callback function to remove. **Must be reference to function added**
function Lock:removeOnRelease(callback)
    self.__callbacks[callback] = nil
end