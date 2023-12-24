local function Logger(path, printToConsole)
    local o = {
        path = path,
        level = 5,
        file = nil,
        print = printToConsole
    }
    o.file = fs.open(path, 'w')
    if not o.file then
        return nil
    end
    function o:setLevel(level)
        self.level = level
    end

    function o:flush()
        self.file.flush()
    end
    function o:write(str)
        self.file.write(str .. '\n')
        self.file.flush()
        if self.print then
            print(str)
        end
    end

    function o:debug(message)
        if self.level < 5 then return end
        self:write('DEBUG: ' .. message)
    end

    function o:info(message)
        if self.level < 4 then return end
        self:write('INFO: ' .. message)
    end

    function o:warn(message)
        if self.level < 3 then return end
        self:write('WARN: ' .. message)
    end

    function o:error(message)
        if self.level < 2 then return end
        self:write('ERROR: ' .. message)
    end

    function o:fatal(message)
        if self.level < 1 then return end
        self:write('FATAL: ' .. message)
    end

    return o
end

return Logger