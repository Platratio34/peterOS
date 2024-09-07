---@package pos.gui
---@class MenuOption : UiElement Basic text input box
---@field name string Menu name
---@field options string[] Menu option names
---@field onSelect fun(index: number, option: string) On option select callback
---@field visible boolean If the dropdown is visible
---@field w number Dropdown width
---@field type string Override. UiElement type field: <code class=string>'MenuOption'</code>
local MenuOption = {
    name = '',
    options = {},
    onSelect = function(index, option) end,
    visible = false,
    type = 'MenuOption'
}
setmetatable(MenuOption, { __index = pos.gui.mt.UiElement })

---Initilizses the option menu
---@param x number X position
---@param name string Menu name
---@param options string[] Option names
---@param w number Dropdown width
---@param onSelect fun(index: number, option: string) On option select callback
function MenuOption:__init__(x, name, options, w, onSelect)
    self.x = x
    self.name = name
    self.w = w
    self.onSelect = onSelect or self.onSelect
    self.options = options
end

---Override. Draws the option menu
---@param window Window Window the option menu is drawn in
---@param windowBuffer FrameBuffer
function MenuOption:draw(window, windowBuffer)
    windowBuffer:write(self.x, 1, self.name, colors.lightGray, self.gray)
    if self.visible then
        windowBuffer:drawRectFilled(colors.gray, self.x, 2, self.x + self.w - 1, 1 + #self.options)
        for i, opt in pairs(self.options) do
            windowBuffer:write(self.x, 1 + i, opt, colors.lightGray)
        end
    end
end
---Override. Processes <code>mouse_click</code> events for the option menu
---@param event table Event table
---@param window Window The window the option menu is processed in
function MenuOption:process(event, window)
    if event[1] == 'mouse_click' then
        local _, _, x, y = table.unpack(event)
        x = x - window.x
        y = y - window.y
        if y == 1 and x >= self.x and x < self.x + string.len(self.name) then
            self.visible = not self.visible
        elseif self.visible and y <= #self.options + 1 then
            if x > self.x and x < self.x + self.w then
                local i = y - 1
                self.onSelect(i, self.options[i])
                return true
            end
        end
    end
    return false
end

---Creates a top bar Menu option
---@constructor MenuOption
---@param x number X position
---@param name string Menu name
---@param options string[] Option names
---@param w number Dropdown width
---@param onSelect fun(index: number, option: string) On select callback
---@return MenuOption menuOption
function pos.gui.MenuOption(x, name, options, w, onSelect)
    local o = {}
    setmetatable(o, { __index = MenuOption })
    o:__init__(x, name, options, w, onSelect)
    return o
end