-- local expect = require "cc.expect"
-- local expect, field = expect.expect, expect.field
local expect = ...

---@class TextBox : UiElement Basic text display box
---@field bg color Background color
---@field fg color Foreground color (text color)
---@field h number Number of lines drawn
---@field _text string Text
---@field _lines string[] Text by lines (generated in <code class=func>setText(<code class=var>text</code>)</code>)
---@field type string Override. UiElement type field: <code class=string>'TextBox'</code>
local TextBox = {
    bg = colors.black,
    fg = colors.white,
    _text = '',
    _lines = {},
    h = 1,
    type = 'TextBox'
}
setmetatable(TextBox, { __index = pos.gui.mt.UiElement })

---Initilizes the TextBox
---@param x number X position
---@param y number Y position
---@param background color|nil Background color
---@param foregroud color|nil Foreground color (text color)
---@param text string text
---@param w number|nil Width of the text box, defaults to length of <code class=var>text</code>
function TextBox:__init__(x, y, background, foregroud, text, w)
    self.x = x
    self.y = y
    self.bg = background or self.bg
    self.fg = foregroud or self.fg
    self.w = w or string.len(text)
    self:setText(text)
end

---Sets the text of the text box, updates line calucations
---@param text string new text
function TextBox:setText(text)
    expect(1, text, 'string')
    self._text = text
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
    self.h = #self._lines
end
---Gets the current text
---@return string text
function TextBox:getText()
    return self._text
end
---Override. Draws the text
---@param window Window Window to draw the text in
function TextBox:draw(window)
    term.setBackgroundColor(self.bg)
    term.setTextColor(self.fg)
    for i, ln in pairs(self._lines) do
        if pos.gui.inWindowRel(window, self.x, self.y + i - 1, self.w, 1) then
            -- pos.gui._log:info(i..','..(self.y + window.y + i - 1)..' | '..ln)
            paintutils.drawFilledBox(self.x + window.x, self.y + window.y + i - 1, self.x + self.w - 1 + window.x, self.y + window.y + i - 1, self.bg)
            term.setCursorPos(self.x + window.x, self.y + window.y + i - 1)
            term.write(ln)
        end
    end
end


---Creates a text box
---@constructor TextBox
---@param x number X coord
---@param y number Y coord
---@param background color|nil Background color
---@param foreground color|nil Text color
---@param text string Text
---@param w number|nil Max line length
---@return TextBox textBox
function pos.gui.TextBox(x, y, background, foreground, text, w)
    local o = {}
    setmetatable(o, {__index = TextBox} )
    o:__init__(x, y, background, foreground, text, w)
    return o
end