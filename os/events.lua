local args = {...}
local log = args[1]
local require = args[2]
local expect = require("cc.expect")

local eventHandlers = {} ---@type table<number, EventHandler>
local eventHandlerId = 0

local osPullEventRaw = os.pullEventRaw
local function pullEventRaw(sFilter)
    while true do
        local event = { osPullEventRaw() }
        local eType = event[1]

        for eId, eHandler in pairs(eventHandlers) do
            local s, r = pcall(function()
                eHandler:try(eType, event)
            end)
            if not s then
                log:error(('Event handler %d error: %s'):format(eId, r))
            end
        end
        
        if not sFilter or sFilter == eType then
            return table.unpack(event)
        end
    end
end
os.pullEventRaw = pullEventRaw

os.pullEvent = function(sFilter)
    local event = { os.pullEventRaw(sFilter) }
    if event[1] == "terminate" then
        error("Terminating", 0)
    end
    return table.unpack(event)
end

---@class EventHandler
---@field handler fun(event: table) Handler function, takes event table
---@field filter nil|string[] Event filter, leave `nil` to handle all events
local EventHandler = {}
---Try to execute the event handler, if filter matchers
---@param eType string event type
---@param event table event table
function EventHandler:try(eType, event)
    if self.filter == nil then
        self.handler(event)
    else
        for _, filter in pairs(self.filter) do
            if filter == eType then
                self.handler(event)
                return
            end
        end
    end
end
---Initialize the event handler
---@param handler fun(event: table) Event handler function, takes event table
---@param filter nil|string|string[] Event type filter. Leave `nil` for all events
function EventHandler:__init__(handler, filter)
    expect(1, handler, "function")
    expect(2, filter, "nil", 'string', 'table')
    self.handler = handler
    if type(filter) == 'string' then
        filter = { filter }
    end
    self.filter = filter
end

---Add an event handler
---@param handler fun(event: table) Event handler function, takes event table
---@param filter nil|string|string[] Event type filter. Leave `nil` for all events
---@return integer handlerId Event handler Id, used to remove handler
function pos.addEventHandler(handler, filter)
    expect(1, handler, "function")
    expect(2, filter, "nil", 'string', 'table')
    local ehId = eventHandlerId
    eventHandlerId = eventHandlerId + 1
    local eventHandler = pos.instanceClass(EventHandler, handler, filter)
    -- setmetatable(eventHandler, { __index = EventHandler })
    -- eventHandler:__init__(handler, filter)
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

---Waits for an event of given type and check function returns true
---@param eventType nil|string event type or nil for all events
---@param check fun(event: table): boolean check function, takes event table, returns true to end wait
function pos.waitForEventCheck(eventType, check)
    while true do
        local event = {os.pullEvent(eventType)}
        if(check(event)) then
            return
        end
    end
end

return {
    EventHandler = EventHandler,
    EventHandlerMT = EventHandler
}