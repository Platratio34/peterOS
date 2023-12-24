local expect = ...

---@package pos.gui
---@class TextInput: UiElement Basic text input box
---@field bg color Background color
---@field fg color Foreground color (text color)
---@field onEnter function On enter function, only called if <code type=var>submitable</code> is true
---@field text string Current text in input
---@field h number Maximum height of input box
---@field focused boolean If the input is currently focused
---@field _lines string[] Parsed lines of text input (generated)
---@field submitable boolean if the input should be treated as submittable, and trigger the <code class=var>onEnter</code> callback
---@field hideText boolean If text in the unput should be hidden an replaced with <code>*</code>s
---@field next UiElement|nil The next input element to be focused on submit or tab
---@field name string|nil Input field name
---@field type string Override. UiElement type field: <code class=string>'TextInput'</code>
local TextInput = {
    bg = colors.gray,
    fg = colors.white,
    onEnter = function(text) end,
    text = '',
    focused = false,
    _lines = {},
    submitable = true,
    type = 'TextInput',
    hideText = false,
    next = nil
}
setmetatable(TextInput, {__index = pos.gui.mt.UiElement} )

---Initilizses the input
---@param x number X position
---@param y number Y position
---@param w number Width
---@param background color|nil Background color
---@param foreground color|nil Text color
---@param onEnter nil|function On Enter function. function(text)
function TextInput:__init__(x, y, w, background, foreground, onEnter)
    self.x = x
    self.y = y
    self.w = w
    self.bg = background or self.bg
    self.fg = foreground or self.fg
    self.onEnter = onEnter or self.onEnter
end

---Set the text of the input
---@param text string New input text
function TextInput:setText(text)
    expect(1, text, 'string')
    self.text = text
    self._lines = {}
    local nls = string.split(text, '\n')
    for _, ln in pairs(nls) do
        if string.len(ln) <= self.w then
            table.insert(self._lines, ln)
        else
            for i = 1, string.len(ln), self.w do
                local lnp = string.sub(ln, i, i + self.w - 1)
                table.insert(self._lines, lnp)
            end
        end
    end
end

---Override. Draws the input box and text
---@param window Window The window the input is drawn in
function TextInput:draw(window)
    if not pos.gui.inWindowRel(window, self.x, self.y, self.w, 1) then return end
    paintutils.drawFilledBox(self.x + window.x, self.y + window.y, self.x + self.w - 1 + window.x, self.y + window.y,
        self.bg)
    term.setBackgroundColor(self.bg)
    term.setTextColor(self.fg)
    -- term.setCursorPos(self.x + window.x, self.y + window.y)
    -- term.write(self.text)
    local lx, ly = self.x + window.x, self.y + window.y
    for i, ln in pairs(self._lines) do
        if pos.gui.inWindowRel(window, self.x, self.y + i - 1, self.w, 1) then
            -- pos.gui._log:info(i..','..(self.y + window.y + i - 1)..' | '..ln)
            paintutils.drawFilledBox(self.x + window.x, self.y + window.y + i - 1, self.x + self.w - 1 + window.x,
                self.y + window.y + i - 1, self.bg)
            term.setCursorPos(self.x + window.x, self.y + window.y + i - 1)
            if self.hideText then
                term.write(string.rep('*', string.len(ln)))
            else
                term.write(ln)
            end
            lx, ly = self.x + window.x + ln:len(), self.y + window.y + i - 1
        end
    end
    if self.focused then
        pos.gui.setCursor(lx, ly, true, self.fg)
    end
end
---Override. Proccesses <code>mouse_click</code>, <code>char</code>, and <code>key</code> events for the input
---@param event table Event table
---@param window Window The window the input is proccessed in
function TextInput:process(event, window)
    if event[1] == 'mouse_click' then
        local _, _, x, y = unpack(event)
        x = x - window.x
        y = y - window.y
        if x >= self.x and x < self.x + self.w and y == self.y then
            self.focused = true
        else
            if self.focused then
                -- pos.gui.setCursor(-1,-1,false,colors.gray)
            end
            self.focused = false
        end
    end
    if not self.focused then
        if self._focusedNext then
            self.focused = true
            self._focusedNext = nil
        end
        return
    end
    if event[1] == 'char' then
        local _, char = unpack(event)
        -- self.text = self.
        if string.len(self.text) < (self.w * self.h) then
            self:setText(self.text .. char)
        end
    elseif event[1] == 'key' then
        local _, key, hold = unpack(event)
        -- pos.gui._log:info(key)
        if key == keys.backspace then
            -- pos.gui._log:info('bakcspace '..self.text)
            if string.len(self.text) > 0 then
                self:setText(self.text:sub(1, -2))
            end
            -- pos.gui._log:info('after '..self.text)
        elseif key == keys.enter or key == keys.numPadEnter then
            if self.submitable then
                if not hold then
                    self.onEnter(self.text)
                    if self.next then
                        self.next._focusedNext = true
                        self.focused = false
                    end
                end
            else
                self:setText(self.text .. '\n')
            end
        elseif key == keys.tab and not hold then
            if self.next then
                self.next._focusedNext = true
                self.focused = false
            end
        end
    end
end

---Sets the max height of the input box
---@param height number Max height
function TextInput:setHeight(height)
    self.h = height
end

---Create a text input box
---@constructor TextInput
---@param x number X coord
---@param y number Y coord
---@param w number Width
---@param background color|nil Background color
---@param foreground color|nil Text color
---@param onEnter nil|function On Enter function. function(text)
---@return TextInput textInput
function pos.gui.TextInput(x, y, w, background, foreground, onEnter)
    local o = {}
    setmetatable(o, { __index = TextInput })
    o:__init__(x, y, w, background, foreground, onEnter)
    return o
end