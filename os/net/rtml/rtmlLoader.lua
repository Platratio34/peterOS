---@module 'os.net.rtml.rtmlLoader'

pos.require('net.rtml')
local loader = {}

---Load an RTML file by filename
---@param filename string Path to file to load and parse
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

---Get XML tag name and attributes
---@param line string Line to parse for XML tag
---@return nil|string name Name of the tag
---@return {string: any}? attributes Attribute table of tag (will be `nil` if tag is closing tag)
---@return boolean? closingTag If the tag is self closing or a closing tag
---@return string? line Remaining portion of line after XML tag
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
    local attributes = {}
    while sI < #line do
        local atrNameEnd, valStart, atrName, nxt = line:find('%s*(%a+)%s*=%s*(.)', sI)
        if not atrNameEnd or not valStart then
            return nil
        end
        if nxt == '"' then
            local valEnd, breakEnd, valStr, valEnder = line:find('%s*"([^"]*)"%s*(/?[,>])%s*',valStart)
            if not valEnd or not breakEnd then
                return nil
            end
            attributes[atrName] = valStr
            if valEnder == '>' or valEnder == '/>' then
                return name, attributes, valEnder == '/>', line:sub(breakEnd+1)
            else
                sI = breakEnd
            end
        else
            local valEnd, breakEnd, valStr, valEnder = line:find('%s*([^,>]+)%s*(/?[,>])%s*', valStart)
            if not valEnd or not breakEnd then
                return nil
            end
            attributes[atrName] = textutils.unserialise(valStr)
            if valEnder == '>' or valEnder == '/>' then
                return name, attributes, valEnder == '/>', line:sub(breakEnd+1)
            else
                sI = breakEnd
            end
        end
    end
    return name, attributes, false, ""
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

    local line = lines[lineN]
    while lineN <= #lines do
        local _, _, linePre, linePost = line:find('([^<]*)(<.*)')
        if not linePre then
            error(('Malformed RTML at line %i, can not parse line'):format(lineN), 2)
        end
        if #linePre > 0 and inTag then
            tempText = tempText .. linePre
        end
        line = linePost
        local tag, attributes, closer, rLine = loader.parseTag(line)
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
                if cElement ~= nil then
                    error(('Malformed RTML at line %i, unclosed tag'):format(lineN), 2)
                end
                cElement = attributes--[[@as RTMLElement]] or {}
                cElement.type = net.rtml.TYPE_TEXT
                if not cElement.x then
                    cElement.x = 1
                end
                if not cElement.y then
                    cElement.y = nextScreenLine
                    nextScreenLine = nextScreenLine + 1
                else
                    nextScreenLine = math.max(nextScreenLine, cElement.y + 1)
                end
                inTag = true
                tempText = ""
                table.insert(parentTree[#parentTree], cElement)
            else
                cElement.text = tempText
                cElement = nil
            end
        elseif tag == 'link' then
            if not closer then
                if cElement ~= nil then
                    error(('Malformed RTML at line %i, unclosed tag'):format(lineN), 2)
                end
                cElement = attributes--[[@as RTMLElement]] or {}
                cElement.type = net.rtml.TYPE_LINK
                if not cElement.x then
                    cElement.x = 1
                end
                if not cElement.y then
                    cElement.y = nextScreenLine
                    nextScreenLine = nextScreenLine + 1
                else
                    nextScreenLine = math.max(nextScreenLine, cElement.y + 1)
                end
                inTag = true
                tempText = ""
                table.insert(parentTree[#parentTree], cElement)
            else
                cElement.text = tempText
                cElement = nil
            end
        elseif tag == 'dom-link' then
            if not closer then
                if cElement ~= nil then
                    error(('Malformed RTML at line %i, unclosed tag'):format(lineN), 2)
                end
                cElement = attributes--[[@as RTMLElement]] or {}
                cElement.type = net.rtml.TYPE_DOM_LINK
                if not cElement.x then
                    cElement.x = 1
                end
                if not cElement.y then
                    cElement.y = nextScreenLine
                    nextScreenLine = nextScreenLine + 1
                else
                    nextScreenLine = math.max(nextScreenLine, cElement.y + 1)
                end
                inTag = true
                tempText = ""
                table.insert(parentTree[#parentTree], cElement)
            else
                cElement.text = tempText
                cElement = nil
            end
        elseif tag == 'button' then
            if not closer then
                if cElement ~= nil then
                    error(('Malformed RTML at line %i, unclosed tag'):format(lineN), 2)
                end
                cElement = attributes--[[@as RTMLElement]] or {}
                cElement.type = net.rtml.TYPE_BUTTON
                if not cElement.x then
                    cElement.x = 1
                end
                if not cElement.y then
                    cElement.y = nextScreenLine
                    nextScreenLine = nextScreenLine + 1
                else
                    nextScreenLine = math.max(nextScreenLine, cElement.y + 1)
                end
                inTag = true
                tempText = ""
                table.insert(parentTree[#parentTree], cElement)
            else
                cElement.text = tempText
                cElement = nil
            end
        elseif tag == 'input' then
            cElement = attributes--[[@as RTMLElement]] or {}
            cElement.type = net.rtml.TYPE_BUTTON
            if not cElement.x then
                cElement.x = 1
            end
            if not cElement.y then
                cElement.y = nextScreenLine
                nextScreenLine = nextScreenLine + 1
            else
                nextScreenLine = math.max(nextScreenLine, cElement.y + 1)
            end
            table.insert(parentTree[#parentTree], cElement)
            if not closer then
                error(('Malformed RTML at line %i, `input` tags must be self closing'):format(lineN), 2)
            end
        elseif inTag then
            local _, _, text = line:find('%s*(.*)')
            tempText = tempText .. text
        end
        if rLine and #rLine > 0 then
            line = rLine
        elseif lineN >= #lines - 1 then
            return
        else
            lineN = lineN + 1
            line = lines[lineN]
        end
    end
end

---Load rtml from plaintext lua object or XML
---@param file string File as string to parse
---@return table? rtml RTML as lua object OR `nil` if it could not be parsed
function loader.load(file)
    if #file < 6 then return nil end
    if file:sub(1, 5) == '<RTML' then
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