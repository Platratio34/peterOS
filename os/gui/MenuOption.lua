---@package pos.gui
---@class MenuOption : UiElement Basic text input box
---@field name string Menu name
---@field options string[] Menu option names
---@field onSelect function On option select callback
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
---@param onSelect function On option select callback
function MenuOption:__init__(x, name, options, w, onSelect)
    self.x = x
    self.name = name
    self.w = w
    self.onSelect = onSelect or self.onSelect
    self.options = options
end

---Override. Draws the option menu
---@param window Window Window the option menu is drawn in
function MenuOption:draw(window)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.lightGray)
    term.setCursorPos(self.x + window.x, 1 + window.y)
    term.write(self.name)
    if self.visible then
        paintutils.drawFilledBox(self.x + window.x, 2 + window.y, self.x + self.w - 1 + window.x,
            1 + #self.options + window.y)
        for i, opt in pairs(self.options) do
            term.setCursorPos(self.x + window.x, 1 + i + window.y)
            term.write(opt)
        end
    end
end
---Override. Proccesses <code>mouse_click</code> events for the option menu
---@param event table Event table
---@param window Window The window the option menu is proccessed in
function MenuOption:process(event, window)
    if event[1] == 'mouse_click' then
        local _, _, x, y = unpack(event)
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
---@param onSelect function On select callback. <code class=func>function(<code class=var>index</code>: <code class=type>number</code>, <code class=var>option</code>: <code class=type>string</code>)</code>
---@return MenuOption menuOption
function pos.gui.MenuOption(x, name, options, w, onSelect)
    local o = {}
    setmetatable(o, { __index = MenuOption })
    o:__init__(x, name, options, w, onSelect)
    return o
end