---@package pos.gui
---@class UiElement Basic UiElement. Defines x, y, w, h, draw, process
---@field x number X origin for element
---@field y number Y origin for element
---@field w number Width of element
---@field h number Height of element
---@field next UiElement|nil The next element to focuse for keyboard navigation (Not impelemted for most elements)
---@field focused boolean If the element is currently focused
---@field _focusedNext boolean If the element should brought into focuse after the curret event
---@field bg color Background color
---@field fg color Foreground color (text color)
---@field type string Type of UiElement, should be overriden by descendants
local UiElement = {
    x = 1,
    y = 1,
    w = 1,
    h = 1,
    bg = colors.black,
    fg = colors.white,
    type = 'UiElement'
}
---Abstract. Draws the UiElement
---@param window Window The window the element will be drawn in
function UiElement:draw(window) end
---Abstract. Processes and event for the element
---@param event table Event table
---@param window Window the window the element is being processed in
function UiElement:process(event, window)
    if self._focusedNext then
        self._focusedNext = false
        self.focused = true
    end
end

---Creates a basic UiElement. Inteded for creating custom UI elements
---@constructor UiElement
---@return UiElement element
function pos.gui.UiElement()
    local o = {}
    setmetatable(o, { __index = UiElement })
    return o
end
pos.gui.mt.UiElement = UiElement