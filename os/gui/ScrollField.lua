---@package pos.gui
---@class ScrollField : UiElement Basic text input box
---@field scroll number Current scroll position
---@field private _elements UiElement[] List of all elements drawn inside the scroll field
---@field private __elementIndex number Index of last added element
---@field type string Override. UiElement type field: <code class=string>'ScrollField'</code>
local ScrollField = {
    scroll = 0,
    _elements = {},
    __elementIndex = 0,
    type = 'ScrollField'
}
setmetatable(ScrollField, { __index = pos.gui.mt.UiElement })

---Initilizes the scroll field
---@param x number X position
---@param y number Y position
---@param w number Width
---@param h number Height
function ScrollField:__init__(x, y, w, h)
    self._elements = {}
    self.x = x
    self.y = y
    self.w = w
    self.h = h
end

---Override. Draws the scroll field and all sub elements
---@param window Window Window the scroll field is drawn in
function ScrollField:draw(window)
    local intWindow = {
        x = window.x + self.x - 1,
        y = window.y + self.y - 1 - self.scroll,
        w = self.w,
        h = self.h,
    }
    paintutils.drawFilledBox(window.x + self.x, window.y + self.y, self.w + window.x + self.x - 1, self.h + window.y + self.y - 1, self.bg)
    for i, el in pairs(self._elements) do
        if not ((el.y + el.h - 1 <= self.scroll) or (el.y > self.h + self.scroll --[[ and el.y + el.h - 1 > self.h + self.scroll]])) then
            -- pos.gui._log:info(i)
            el:draw(intWindow)
        end
    end
end
---Override. Proccesses <code>mouse_scroll</code> events for the scroll field
---@param event table Event table
---@param window Window The window the scroll field is proccessed in
function ScrollField:process(event, window)
    if event[1] == 'mouse_scroll' then
        local _, dir, x, y = unpack(event)
        x = x - window.x
        y = y - window.y
        -- pos.gui._log:debug('thinging')
        if pos.gui.inBox(window, self.x, self.y, self.w, self.h, x, y) then
            self.scroll = self.scroll + dir
            local max = 0
            for _, el in pairs(self._elements) do
                -- pos.gui._log:debug(el.y + el.h - 1)
                max = math.max(max, el.y + el.h - 1)
            end
            -- log:debug(max)
            max = math.max(0, max - self.h)
            -- log:debug(max)
            if self.scroll < 0 then
                self.scroll = 0
            elseif self.scroll > max then
                self.scroll = max
                -- pos.gui._log:debug('scroll max '..max)
            end
        end
    end
    local intWindow = {
        x = window.x + self.x - 1,
        y = window.y + self.y - self.scroll - 1,
        w = self.w,
        h = self.h,
    }
    -- pos.gui._log:debug(tostring(self._elements))
    local t = {}
    for i, el in pairs(self._elements) do
        t[i] = el
    end
    for _, el in pairs(t) do
        el:process(event, intWindow)
    end
end

---Add a element to the scroll field
---@param element UiElement Element to add
---@return number index Element index in the scroll field
function ScrollField:addElement(element)
    local index = self.__elementIndex
    self._elements[index] = element
    self.__elementIndex = self.__elementIndex + 1
    return index
end
---Remove an element from the scroll field by index
---@param index number Index of element to remove
function ScrollField:removeElement(index)
    self._elements[index] = nil
end
---Clears all elemetns from scroll field. Next element will be id 0
function ScrollField:clearElements()
    self._elements = {}
    self.__elementIndex = 0
    self.scroll = 0
end

---Creates a scrollable field
---@constructor ScrollField
---@param x number X coord
---@param y number Y Coord
---@param w number Width
---@param h number Height
---@return ScrollField scrollField
function pos.gui.ScrollField(x, y, w, h)
    local o = {}
    setmetatable(o, { __index = ScrollField })
    o:__init__(x,y,w,h)
    return o
end