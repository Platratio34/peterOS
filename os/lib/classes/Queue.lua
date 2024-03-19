---@package pos

---@class Queue Generic Queue data structure
---@field private __arr any[]
---@field private __first number
---@field private __last number
local Queue = {}
local QueueMT = {
    __index = Queue
}

---Instantiate a new queue
---@return Queue queue
local function instantiate()
    local o = {}
    setmetatable(o, QueueMT)
    o:__init__()
    return o
end
_G.pos.Queue = instantiate

---**Internal** initialize the queue
---@private
function Queue:__init__()
    self.__arr = {}
    self.__first = 0
    self.__last = -1
end

---Adds an item to the end of the queue
---@param item any
function Queue:enqueue(item)
    self.__last = self.__last + 1
    self.__arr[self.__last] = item
end

---Removes the first item from the queue and return it
---@return nil|any item
function Queue:dequeue()
    if (self.__first > self.__last) then
        return nil
    end
    local item = self.__arr[self.__first]
    self.__arr[self.__first] = nil
    self.__first = self.__first + 1
    return item
end

---Return the fist item in the queue without removing it
---@return nil|any item
function Queue:peek()
    if (self.__first > self.__last) then
        return nil
    end
    local item = self.__arr[self.__first]
    return item
end

---Get the number of items in the queue
---@return number size
function Queue:size()
    return self.__last - self.__first + 1
end

---Clear all items from the queue
function Queue:clear()
    self.__arr = {}
    self.__first = 0
    self.__last = -1 
end