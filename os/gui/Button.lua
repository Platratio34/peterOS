---@package pos.gui
---@class Button : UiElement Basic GUI button
---@field bg color Background color
---@field fg color Foreground color (text color)
---@field text string Button text
---@field onClick function On button click callback, passes mouse button used to click
---@field type string Override. UiElement type field: <code class=string>'Button'</code>
local Button = {
    bg = colors.gray,
    fg = colors.white,
    text = '',
    onClick = function(button) end,
    type = 'Button',
}
setmetatable(Button, {__index = pos.gui.mt.UiElement} )

---Initilizses the button
---@param x number X position
---@param y number Y position
---@param w number Width
---@param h number Height
---@param background color|nil Background color
---@param foreground color|nil Foreground color (text color)
---@param text string Button text
---@param onClick function On Click callback, passed mouse button
function Button:__init__(x, y, w, h, background, foreground, text, onClick)
    self.x = x
    self.y = y
    self.w = w
    self.h = h
    self.bg = background or self.bg
    self.fg = foreground or self.fg
    self.text = text
    self.onClick = onClick
end

---Override. Draws the button
---@param window Window Window to draw the button in
function Button:draw(window)
    -- pos.gui._log:debug('- showing btn '..self.text)
    if not pos.gui.inWindowRel(window, self.x, self.y, self.w, self.h) then return end
    paintutils.drawFilledBox(self.x + window.x, self.y + window.y, self.x + self.w - 1 + window.x,
        self.y + self.h - 1 + window.y, self.bg)
    term.setBackgroundColor(self.bg)
    term.setTextColor(self.fg)
    term.setCursorPos(self.x + window.x, self.y + window.y)
    term.write(self.text)
end
---Override. Proccesses <code>mouse_click</code> events for the button
---@param event table Event table
---@param window Window The window the button is proccessed in
function Button:process(event, window)
    if event[1] == 'mouse_click' then
        local _, btn, x, y = unpack(event)
        x = x - window.x
        y = y - window.y
        if x >= self.x and x < self.x + self.w and y >= self.y and y < self.y + self.h then
            self.onClick(btn)
        end
    end
end

---Creates a clickable button
---@constructor Button
---@param x number X position
---@param y number Y position
---@param w number Width
---@param h number Height
---@param background color|nil Background color
---@param foreground color|nil Text color
---@param text string Button text
---@param onClick function On Click callback, passed mouse button
---@return Button button
function pos.gui.Button(x, y, w, h, background, foreground, text, onClick)
    local o = {}
    setmetatable(o, { __index = Button })
    o:__init__(x, y, w, h, background, foreground, text, onClick)
    return o
end