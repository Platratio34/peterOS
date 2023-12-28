local expect = require "cc.expect"

local log = pos.Logger('/home/.pgmLog/pos.gui.log')
log:info('Starting GUI')

---@alias color number

local gui = {}
gui._log = log
log:setLevel(pos.LoggerLevel.INFO)
---Sets the Logger for gui, if not set is /home/.pgmLog/pos.gui.log with full log
---@param newLog Logger PeterOS logger to be used by GUI functions
function gui.setLog(newLog)
    log = newLog
    gui._log = log
end

---PeterOS Graphical User Interface package
_G.pos.gui = gui

---Collection of meta tables
---@type table
gui.mt = {}

--- INTERNAL gui information
local _gui = {}

function gui.inWindow(window, x, y, w, h)
    if x <= window.x or x > window.x + window.w then
        return false
    end
    if y <= window.y or y > window.y + window.h then
        return false
    end
    local x2 = x + w - 1
    local y2 = y + h - 1
    if x2 <= window.x or x2 > window.x + window.w then
        return false
    end
    if y2 <= window.y or y2 > window.y + window.h then
        return false
    end
    return true
end
function gui.inWindowRel(window, x, y, w, h)
    return true
    -- if x <= 0 or x > window.w then
    --     return false
    -- end
    -- if y <= 0 or y > window.h then
    --     return false
    -- end
    -- local x2 = x + w - 1
    -- local y2 = y + h - 1
    -- if x2 <= 0 or x2 > window.w then
    --     return false
    -- end
    -- if y2 <= 0 or y2 > window.h then
    --     return false
    -- end
    -- return true
    -- return gui.inWindow(window, x, y, w, h)
end

function gui.inBox(window, bx, by, bw, bh, x, y)
    -- bx = bx + window.x
    -- by = by + window.y
    local bx2 = bx + bw - 1
    local by2 = by + bh - 1

    log:debug(bx .. ',' .. by .. ' - ' .. bx2 .. ',' .. by2 .. ' in ' .. x .. ',' .. y)

    if x < bx or x > bx2 then
        return false
    end
    if y < by or y > by2 then
        return false
    end
    return true
end

_gui.windows = {}
_gui.windowIndex = 0
_gui.windowOrder = {} ---@type number[]

_gui.focusedWindow = -1 ---@type number

---Add a window to gui system
---@param window Window Window (from Window())
---@return integer id Window id
function gui.addWindow(window)
    local index = _gui.windowIndex
    _gui.windows[index] = window
    log:debug('Added window ' .. index)
    _gui.windowIndex = _gui.windowIndex + 1
    window._windowIndex = index
    return index
end
---Remove a window
---@param window Window|number window or window index
function gui.removeWindow(window)
    if type(window) == 'table' then
        window = window._windowIndex
    end
    _gui.windows[window]._windowIndex = -1
    _gui.windows[window] = nil
    for o, i in pairs(_gui.windowOrder) do
        if i == window then
            table.remove(_gui.windowOrder, o)
        end
    end
end

_gui.cursor = {
    x = -1,
    y = -1,
    active = false,
    color = colors.white,
}
---Set the cursor position and if it should be blinking
---@param x number X coord
---@param y number Y coord
---@param active boolean Cursor blink
---@param color number Cursor color
function gui.setCursor(x,y,active,color)
    _gui.cursor.x = x
    _gui.cursor.y = y
    _gui.cursor.active = active
    _gui.cursor.color = color
    log:debug('set cursor: '..x..','..y..' '..tostring(active))
end

---INTERNAL | Redraws all windows in system
function gui.redrawWindows()
    term.setBackgroundColor(colors.black)
    term.clear()
    -- for i, window in pairs(_gui.windows) do
    --     log:debug('w '..i)
    --     if window.visible then
    --         window:draw()
    --         log:debug('- '..i..' visible')
    --     end
    -- end
    log:debug('drawing all windows')
    for i = #(_gui.windowOrder), 1, -1 do
        local wIndex = _gui.windowOrder[i]
        local window = _gui.windows[wIndex]
        log:debug('w ' .. wIndex .. ' ' .. tostring(window.visible))
        if window.visible then
            window:draw()
        end
    end
    if _gui.cursor.active then
        term.setTextColor(_gui.cursor.color)
        term.setCursorPos(_gui.cursor.x, _gui.cursor.y)
    end
    term.setCursorBlink(_gui.cursor.active)
    _gui.cursor.active = false
end
---INTERNAL | Processes and event for all windows in system
---@param event table Event table
function gui.processWindows(event)
    -- for i, window in pairs(_gui.windows) do
    --     log:debug('p ' .. i)
    --     if window.visible then
    --         window:process(event)
    --         log:debug('- ' .. i .. ' visible')
    --     end
    -- end
    if _gui.focusedWindow >= 0 then
        _gui.windows[_gui.focusedWindow]:process(event)
    end
end

---Focus window
---@param window Window|number  window or window index
function gui.focusWindow(window)
    if type(window) == 'table' then
        window = window._windowIndex
        ---@cast window number
    end
    if not _gui.windows[window] then
        return
    end
    _gui.focusedWindow = window
    for o, i in pairs(_gui.windowOrder) do
        if i == window then
            table.remove(_gui.windowOrder, o)
        end
    end
    table.insert(_gui.windowOrder, 1, window)
end
---Unfocuse window
---@param window Window|number  window or window index
function gui.unfocuseWindow(window)
    if type(window) == 'table' then
        window = window._windowIndex
        ---@cast window number
    end
    if not _gui.windows[window] then
        return
    end
    if _gui.windowOrder[1] == window then
        table.remove(_gui.windowOrder, 1)
        if #_gui.windowOrder > 0 then
            _gui.focusedWindow = _gui.windowOrder[1]
        else
            _gui.focusedWindow = -1
        end
    end
end

---@type boolean If window system is running. Set to false to stop running
gui.running = false
---Run window draw and process loop. Runs until pos.gui.running is set to false
---@param func nil|function (Optional) Event function. function(eventTable)
function gui.run(func)
    _gui.lError = {}
    gui.running = true
    while gui.running do
        local event = { os.pullEventRaw() }
        if event[1] == 'terminate' then
            gui.running = false
            break
        end
        local s, e = pcall(gui.processWindows, event)
        if not s then
            gui.running = false
            log:fatal('Encounterd error in proccessing windows:')
            log:fatal(e)
            table.insert(_gui.lError, 'Process Error:')
            table.insert(_gui.lError, e)
        end
        if func then
            s, e = pcall(func, event)
            if not s then
                gui.running = false
                log:fatal('Encounterd error in event function:')
                log:fatal(e)
                table.insert(_gui.lError, e)
            end
        end
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()
        s, e = pcall(gui.redrawWindows)
        if not s then
            gui.running = false
            log:fatal('Encounterd error in drawing windows:')
            log:fatal(e)
            table.insert(_gui.lError, 'Draw Error:')
            table.insert(_gui.lError, e)
        end
    end
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    for _,error in pairs(_gui.lError) do
        printError(error)
    end
end

local classes = {
    'Window',
    'UiElement',
    'TextBox',
    'Button',
    'TextInput',
    'MenuOption',
    'ScrollField',
    'ListField',
    'FileSelector'
}
for _,class in pairs(classes) do
    -- shell.run('/os/gui/'..class..'.lua')
    loadfile('/os/gui/'..class..'.lua')(expect)
end