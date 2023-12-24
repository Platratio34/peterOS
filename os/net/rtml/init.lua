local rtml = {}

---@class RTMLElement
---@field type string Element type
---@field x number X position of the element
---@field y number Y position of the element
---@field color nil|color|string Element forground color
---@field bgColor nil|color|string Element background color
---@field id nil|string Element ID
---@field text nil|string Element text
---@field href nil|string Link url
---@field name nil|string (Form Element Only) Element name
---@field len nil|number (Input Only) Length of element
---@field hide nil|boolean (Input Only) If input text should be hidden
---@field action nil|string (Button Only) Button action

---Create a new typed RTMLElement
---@param type string Element type (one of <code>net.rtml.TYPE_*</code>)
---@param x number X position of the element
---@param y number Y position of the element
---@return RTMLElement
function rtml.createElement(type, x, y)
    return { type = type, x = x, y = y } ---@type RTMLElement
end

---Create a new text element
---@param x number X position
---@param y number Y position
---@param text string Element text
---@param color color|nil (Optional) Text color
---@return RTMLElement
function rtml.createText(x, y, text, color)
    local el = rtml.createElement(rtml.TYPE_TEXT, x, y)
    el.text = text
    el.color = color
    return el
end

---Create a new link element
---@param x number X position
---@param y number Y position
---@param text string Element text
---@param href string Link destinaiton, can be absolute (<code>"/path"</code>), or relative (<code>"path"</code>)
---@return RTMLElement
function rtml.createLink(x, y, text, href)
    local el = rtml.createElement(rtml.TYPE_LINK, x, y)
    el.text = text
    el.href = href
    return el
end

---Create a new input element
---@param x number X position
---@param y number Y position
---@param length number Input length
---@param name string Input name for forms
---@param hide boolean|nil (Optional) If input text should be hidden
---@return RTMLElement
function rtml.createInput(x, y, length, name, hide)
    local el = rtml.createElement(rtml.TYPE_INPUT, x, y)
    el.len = length
    el.name = name
    el.hide = hide
    return el
end

---Create a new button element
---@param x number X position
---@param y number Y position
---@param text string Button text
---@param action string Button action (one of <code>net.rtml.BUTTON_ACTION_*</code>)
---@return RTMLElement
function rtml.createButton(x, y, text, action)
    local el = rtml.createElement(rtml.TYPE_BUTTON, x, y)
    el.text = text
    el.action = action
    return el
end
---Create a new submit button element (equivalent to setting <code>action</code> to <code>"SUBMIT"</code> for <code>createButton()</code>)
---@param x number X position
---@param y number Y position
---@param text string Button text
---@return RTMLElement
function rtml.createSubmitButton(x, y, text)
    return rtml.createButton(x, y, text, rtml.BUTTON_ACTION_SUBMIT)
end

---@class RTMLContext
---@field elements RTMLElement[] context elements
local RTMLContext = {
    elements = {}
}

---Create a new RTML context (equivelent to a window)
---@return RTMLContext context
function rtml.createContext()
    local context = {
        elements = {}
    }
    setmetatable(context, { __index = RTMLContext })
    return context
end

---Add an RTMLElement to the context
---@param element RTMLElement Element to add
function RTMLContext:addElement(element)
    table.insert(self.elements, element)
end

---Add a new text element
---@param x number X position
---@param y number Y position
---@param text string Element text
---@param color color|nil (Optional) Text color
function RTMLContext:addText(x, y, text, color)
    self:addElement(rtml.createText(x, y, text, color))
end
---Add a new link element
---@param x number X position
---@param y number Y position
---@param text string Element text
---@param href string Link destinaiton, can be absolute (<code>"/path"</code>), or relative (<code>"path"</code>)
function RTMLContext:addLink(x, y, text, href)
    self:addElement(rtml.createLink(x, y, text, href))
end
---Add a new input element
---@param x number X position
---@param y number Y position
---@param length number Input length
---@param name string Input name for forms
---@param hide boolean|nil (Optional) If input text should be hidden
function RTMLContext:addInput(x, y, length, name, hide)
    self:addElement(rtml.createInput(x, y, length, name, hide))
end
---Add a new button element
---@param x number X position
---@param y number Y position
---@param text string Button text
---@param action string Button action (ie. <code>SUBMIT</code>)
function RTMLContext:addButton(x, y, text, action)
    self:addElement(rtml.createButton(x, y, text, action))
end
---Add a new submit button element (equivalent to setting <code>action</code> to <code>"SUBMIT"</code> for <code>addButton()</code>)
---@param x number X position
---@param y number Y position
---@param text string Button text
function RTMLContext:addSubmitButton(x, y, text)
    self:addElement(rtml.createSubmitButton(x, y, text))
end

rtml.TYPE_TEXT = "TEXT"
rtml.TYPE_INPUT = "INPUT"
rtml.TYPE_LINK = "LINK"
rtml.TYPE_DOMAIN_LINK = "DOM-LINK"
rtml.TYPE_BUTTON = "BUTTON"

rtml.BUTTON_ACTION_SUBMIT = 'SUBMIT'
rtml.BUTTON_ACTION_PUSH = 'PUSH'

net.rtml = rtml