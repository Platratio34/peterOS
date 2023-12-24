---@package pos.gui
---@class FileSelector File selector GUI window
---@field root string Current file path
---@field action string Action button text (Read Only)
---@field onAction function On action callback, passes path to file and file selector window object
---@field w number Window width (Read Only)
---@field h number Window height (Read Only)
---@field private _p table GUI element table
---@field _p.window Window Selector window
---@field _p.windowIndex number Window index
---@field _p.pathInput TextInput Path input
---@field _p.scrollField ScrollField File scroll field
---@field _p.fileInput TextInput File name input
---@field _p.upBtn Button Navigate up path button
---@field _p.fileBtns Button[] File select buttons
local FileSelector = {
    root = '/home/',
    action = 'Select',
    onAction = function(file, window) end,
    w = 30,
    h = 15,

    _p = {
        window = nil,
        windowIndex = -1,
        pathInput = nil,
        scrollField = nil,
        fileInput = nil,
        upBtn = nil,
        fileBtns = {},
    }
}
-- -- -- setmetatable(FileSelector, { __index = pos.gui.mt.UiElement })

function FileSelector:__constructor__()
    local window = pos.gui.Window('File Selector', colors.blue)
    window.visible = false
    window.exitOnHide = false
    self._p.window = window
    window:setSize(self.w, self.h)
    window:setPos(8, 3)
    self._p.windowIndex = pos.gui.addWindow(window)

    local pathInput = pos.gui.TextInput(1,2,self.w,colors.gray,colors.white, function(text)
        self:updateFiles(text)
    end)
    self._p.pathInput = pathInput
    window:addElement(pathInput)

    local scrollField = pos.gui.ScrollField(1, 3, self.w, self.h - 3)
    scrollField.bg = colors.blue
    self._p.scrollField = scrollField
    window:addElement(scrollField)

    local actionLength = string.len(self.action)
    local fileInput = pos.gui.TextInput(1, self.h, self.w-actionLength+1, colors.gray, colors.white, function(text)
        self.onAction(self.root..text, self._p.window)
    end)
    self._p.fileInput = fileInput
    window:addElement(fileInput)
    
    local actionBtn = pos.gui.Button(self.w-actionLength+1,self.h,actionLength,1,colors.lightGray,colors.black,self.action,function(btn)
        self.onAction(self.root..fileInput.text, self._p.window)
    end)
    self._p.actionBtn = actionBtn
    window:addElement(actionBtn)

    local upBtn = pos.gui.Button(1,1,self.w,1,colors.blue,colors.green,'..',function(btn)
        if self.root == '/' then
            return
        end
        local pParts = self.root:split('/')
        self:updateFiles(table.concat(pParts, '/', 1, #pParts - 2))
    end)
    self._p.upBtn = upBtn
    scrollField:addElement(upBtn)

    self:updateFiles(self.root)
    self:hide()
end

function FileSelector:updateFiles(path)
    if path == '' then path = '/' end
    if not path:ends('/') then path = path .. '/' end
    self.root = path
    self._p.pathInput:setText(path)
    self._p.fileInput:setText('')

    local sF = self._p.scrollField
    sF.scroll = 0

    for index, _ in pairs(self._p.fileBtns) do
        ---@diagnostic disable-next-line: need-check-nil
        sF:removeElement(index)
    end
    local fileBtns = {}
    self._p.fileBtns = fileBtns

    local files = fs.list(self.root)
    if not files then
        return
    end
    ---@cast files string[]
    for i, file in pairs(files) do
        local isDir = fs.isDir(self.root .. file)
        local btn = pos.gui.Button(1,i+1,self.w,1,colors.blue,colors.white,file,function(btn)
            if isDir then
                self:updateFiles(self.root..file)
            else
                if self._p.fileInput.text == file then
                    self.onAction(self.root..self._p.fileInput.text, self._p.window)
                end
                self._p.fileInput:setText(file)
            end
        end)
        if isDir then
            btn.fg = colors.green
        end
        ---@diagnostic disable-next-line: need-check-nil
        local index = sF:addElement(btn)
        fileBtns[index] = btn
    end
end

function FileSelector:dispose()
    pos.gui.removeWindow(self._p.windowIndex)
end

function FileSelector:show()
    self._p.window:show()
end
function FileSelector:hide()
    self._p.window:hide()
end

function FileSelector:setAction(action, onAction)
    self.action = action or self.action
    self.onAction = onAction or self.onAction
    local actionLength = string.len(self.action)
    self._p.actionBtn.text = action
    self._p.actionBtn.x = self.w-actionLength+1
    self._p.actionBtn.w = actionLength
    
    self._p.fileInput.w = self.w-actionLength+1
end

---Create a file selector GUI
---@constructor FileSelector
---@param root string starting path of the selector
---@param action string select button text
---@param onAction function On action event, function(path, fileSelectorWindow)
---@return FileSelector fileSelector
function pos.gui.FileSelector(root, action, onAction)
    local o = {
        root = root,
        action = action,
        onAction = onAction,
    }
    setmetatable(o, { __index = FileSelector })
    o:__constructor__()
    return o
end