---@package pos.gui
---@class Window Basic GUI window class
---@field bg color Backgroud color
---@field private _name string Window name
---@field visible boolean Window visibility
---@field exitOnHide boolean If the window should exit the program on being hidden
---@field x number Window X origin
---@field y number Window Y origin
---@field w number Window width
---@field h number Window height
---@field hideNameBar boolean If the name bar should be hidden for the window
---@field private _elements UiElement[] Table of elements in window
---@field private __elementIndex number Last element index
---@field private _menuOptions MenuOption[] Table of menu options for window bar
---@field private __menuIndex number Last menu option index
---@field private _nameOffset number Name x offset (calulated)
---@field _windowIndex number Global window index (set by <code class=func>pos.gui.addWindow()</code>)
local Window = {
    bg = colors.black,
    _name = '',
    visible = false,
    exitOnHide = true,
    x = 0,
    y = 0,
    w = 1,
    h = 1,
    _elements = {},
    __elementIndex = 0,
    _menuOptions = {},
    __menuIndex = 0,
    _nameOffset = 0,
    _windowIndex = -1,
    hideNameBar = false
}
Window.w, Window.h = term.getSize()

---Initializes the window
---@param name string window name
---@param background number background color
function Window:__init__(name, background)
    self.bg = background or self.bg
    self._elements = {}
    self._menuOptions = {}
    self.w, self.h = term.getSize()
    self:setName(name)
end

---Set window visible
function Window:show()
    self.visible = true
    pos.gui.focusWindow(self._windowIndex)
end
---Set window not visible
function Window:hide()
    self.visible = false
    if self.exitOnHide then
        pos.gui.running = false
    end
    pos.gui.unfocuseWindow(self._windowIndex)
end

---Draw window
function Window:draw()
    -- pos.gui._log:debug('showing window '..self._name)
    paintutils.drawFilledBox(1 + self.x, 1 + self.y, self.w + self.x, self.h + self.y, self.bg)
    for _, el in pairs(self._elements) do
        if el.visible then
            -- pos.gui._log:debug('drawing '..el.type)
            el:draw(self)
            -- if el.type == 'button' then
            --     pos.gui._log:debug('+drawing btn '..el.text)
            -- end
        end
    end
    term.setBackgroundColor(colors.gray)
    if not self.hideNameBar then
        paintutils.drawFilledBox(1 + self.x, 1 + self.y, self.w + self.x, 1 + self.y, colors.gray)
        term.setTextColor(colors.white)
        term.setCursorPos(self._nameOffset + self.x, 1 + self.y)
        term.write(self._name)
    end
    term.setTextColor(colors.red)
    term.setCursorPos(self.w + self.x, 1 + self.y)
    term.write('X')

    for _, mo in pairs(self._menuOptions) do
        mo:draw(self)
    end
    -- pos.gui._log:debug('done rendering window '..self._name)
end
---Process event for window
---@param event table Event table
function Window:process(event)
    if event[1] == 'mouse_click' then
        local _, button, x, y = unpack(event)
        x = x - self.x
        y = y - self.y
        if y == 1 and x == self.w then
            self:hide()
            return
        end
    end
    
    local moa = false
    for _, el in pairs(self._menuOptions) do
        moa = moa or el:process(event, self)
    end
    if moa then
        return
    end
    
    local t = {}
    for i, el in pairs(self._elements) do
        t[i] = el
    end
    for _, el in pairs(t) do
        if el.visible then
            el:process(event, self)
        end
    end
end

---Add a UIElement to the window
---@param element UiElement Element to add
---@return number index Element index, used to remove the element later
function Window:addElement(element)
    local index = self.__elementIndex
    if self._elements[index] then
        pos.gui._log:error('Element '..index..' already existed for '..self._name)
        return -1
    end
    self._elements[index] = element
    self.__elementIndex = self.__elementIndex + 1
    -- pos.gui._log:debug('added element '..index..' to '..self._name)
    return index
end
---Removes a UiElement by index
---@param index number Element index
function Window:removeElement(index)
    self._elements[index] = nil
end

---Adds a MenuOption to the window
---@param option MenuOption Menu option
---@return number index Option index, used for removal
function Window:addMenuOption(option)
    local index = self.__menuIndex
    self._menuOptions[index] = option
    self.__menuIndex = self.__menuIndex + 1
    return index
end
---Removes a menu option by index
---@param index number Option index
function Window:removeMenuOption(index)
    self._menuOptions[index] = nil
end

---Set the window name
---@param name string Window name
function Window:setName(name)
    -- pos.gui._log:debug('changing window name from "'..self._name..'" to "'..name..'"')
    self._name = name
    self._nameOffset = (self.w / 2) - (string.len(self._name) / 2)
end
---Get the current name of this window
---@return string name
function Window:getName()
    return self._name
end

---Set the location of the window (offset location not pixel location)
---@param x number
---@param y number
function Window:setPos(x, y)
    self.x = x
    self.y = y
end
---Set the size of the window
---@param w number
---@param h number
function Window:setSize(w, h)
    self.w = w
    self.h = h
    self._nameOffset = (self.w / 2) - (string.len(self._name) / 2)
end

---Create a new window
---@constructor Window
---@param name string Window name, displayed in center of top bar
---@param background nil|number Window background color
---@return Window window
function pos.gui.Window(name, background)
    local o = {}
    setmetatable(o, { __index = Window })
    o:__init__(name, background)
    return o
end