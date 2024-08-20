---@module 'os.net.rtml.rtmlLoader'

local loader = {}

---Load an RTML file by filename
---@param filename string
---@return table? rtml RTML as lua object OR `nil` if it could not be parsed
function loader.loadFile(filename)
    local f = fs.open(filename, 'r')
    if not f then
        error("Unable to open file", 2)
    end
    local rtml = loader.load(f.readAll())
    f.close()
    return rtml
end

---Get XML tag name and options
---@param line string
---@return nil|string name
---@return table? options
---@return boolean? closingTag
---@return string? line
function loader.parseTag(line)
    local _, sI, name, nameEnder = line:find('%s*<(%a+)%s*(/?>?)%s*')
    if not sI then
        local _, tagEnd, tagName = line:find('%s*</(%a+)%s*>%s*')
        if tagName then
            return tagName, nil, true, line:sub(tagEnd+1)
        end
        return nil
    end
    if nameEnder == '>' or nameEnder == '/>' then
        return name, {}, nameEnder == '/>', line:sub(sI+1)
    end
    local options = {}
    while sI < #line do
        local optNameEnd, valStart, optName, nxt = line:find('%s*(%a+)%s*=%s*(.)', sI)
        if not optNameEnd or not valStart then
            return nil
        end
        if nxt == '"' then
            local valEnd, breakEnd, valStr, valEnder = line:find('%s*"([^"]*)"%s*(/?[,>])%s*',valStart)
            if not valEnd or not breakEnd then
                return nil
            end
            options[optName] = valStr
            if valEnder == '>' or valEnder == '/>' then
                return name, options, valEnder == '/>', line:sub(breakEnd+1)
            else
                sI = breakEnd
            end
        else
            local valEnd, breakEnd, valStr, valEnder = line:find('%s*([^,>]+)%s*(/?[,>])%s*', valStart)
            if not valEnd or not breakEnd then
                return nil
            end
            options[optName] = textutils.unserialise(valStr)
            if valEnder == '>' or valEnder == '/>' then
                return name, options, valEnder == '/>', line:sub(breakEnd+1)
            else
                sI = breakEnd
            end
        end
    end
    return name, options, false
end

---Load rtml from plaintext XML in version 1
---@param lines string[]
local function loadV1(rtml, lines)
    local lineN = 2

    local parentTree = {{}}

    local inBody = false
    local cElement = nil ---@type RTMLElement?
    local nextScreenLine = 1

    local tempText = "" ---@type string?
    local inTag = false

    while lineN <= #lines do
        local line = lines[lineN]
        local tag, options, closer, rLine = loader.parseTag(line)
        if tag == 'body' then
            if not closer then
                table.insert(parentTree, rtml)
            else
                if not parentTree[#parentTree] == rtml then
                    error(('Malformed RTML at line %i, unclosed tag'):format(lineN), 2)
                end
            end
        elseif tag == 'text' then
            if not closer then
                cElement = options or {} ---@cast options RTMLElement
                cElement.type = net.rtml.TYPE_TEXT
                if not cElement.x then
                    cElement.x = 1
                end
                if not cElement.y then
                    cElement.y = nextScreenLine
                    nextScreenLine = nextScreenLine + 1
                else
                    nextScreenLine = math.max(nextScreenLine, cElement.y+1)
                end
                inTag = true
                tempText = rLine
                table.insert(parentTree[#parentTree], cElement)
            else
                cElement.text = tempText
            end
        elseif tag == 'link' then
            if not closer then
                cElement = options or {} ---@cast options RTMLElement
                cElement.type = net.rtml.TYPE_LINK
                if not cElement.x then
                    cElement.x = 1
                end
                if not cElement.y then
                    cElement.y = nextScreenLine
                    nextScreenLine = nextScreenLine + 1
                else
                    nextScreenLine = math.max(nextScreenLine, cElement.y+1)
                end
                inTag = true
                tempText = rLine
                table.insert(parentTree[#parentTree], cElement)
            else
                cElement.text = tempText
            end
        elseif tag == 'dom-link' then
            if not closer then
                cElement = options or {} ---@cast options RTMLElement
                cElement.type = net.rtml.TYPE_DOM_LINK
                if not cElement.x then
                    cElement.x = 1
                end
                if not cElement.y then
                    cElement.y = nextScreenLine
                    nextScreenLine = nextScreenLine + 1
                else
                    nextScreenLine = math.max(nextScreenLine, cElement.y+1)
                end
                inTag = true
                tempText = rLine
                table.insert(parentTree[#parentTree], cElement)
            else
                cElement.text = tempText
            end
        elseif tag == 'button' then
            if not closer then
                cElement = options or {} ---@cast options RTMLElement
                cElement.type = net.rtml.TYPE_BUTTON
                if not cElement.x then
                    cElement.x = 1
                end
                if not cElement.y then
                    cElement.y = nextScreenLine
                    nextScreenLine = nextScreenLine + 1
                else
                    nextScreenLine = math.max(nextScreenLine, cElement.y+1)
                end
                inTag = true
                tempText = rLine
                table.insert(parentTree[#parentTree], cElement)
            else
                cElement.text = tempText
            end
        elseif tag == 'input' then
            cElement = options or {} ---@cast options RTMLElement
            cElement.type = net.rtml.TYPE_BUTTON
            if not cElement.x then
                cElement.x = 1
            end
            if not cElement.y then
                cElement.y = nextScreenLine
                nextScreenLine = nextScreenLine + 1
            else
                nextScreenLine = math.max(nextScreenLine, cElement.y+1)
            end
            table.insert(parentTree[#parentTree], cElement)
            if not closer then
                error(('Malformed RTML at line %i, `input` tags must be self closing'):format(lineN), 2)
            end
        elseif inTag then
            tempText = tempText .. line:find('%s*(.*)')
        end
        lineN = lineN + 1
    end
end

---Load rtml from plaintext lua object or XML
---@param file string
---@return table? rtml RTML as lua object OR `nil` if it could not be parsed
function loader.load(file)
    if #file < 6 then return nil end
    if file:sub(1, 6) == '<RTML>' then
        local rtml = {}
        local lines = file:split('\n')
        local _, rtmlOptions = loader.parseTag(lines[1])
        rtml.header = rtmlOptions or { version = 1 }
        if rtml.header.version == 1 then
            loadV1(rtml, lines)
        else
            error("Unknown RTML file version. Valid versions: 1", 2)
        end
        return rtml
    else
        return textutils.unserialise(file)
    end
end

return loader