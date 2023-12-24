pos.require("net.rttp")

-- local rttp = pos.require("rttp")
-- local server = rttp.server

local serverCfgF = fs.open("/home/www/server.cfg", "r")
if serverCfgF ~= nil then
    local serverCfg = textutils.unserialise(serverCfgF.readAll())
    serverCfgF.close()

    -- server.setup(serverCfg.side, serverCfg.domain)

    -- local runing = true

    -- while runing do
    --     local msg = server.waitForMsg()
    rttp.handleMsg(function(method,head,body,msg)
        if method == "GET" then
            if head.path == "" then
                return 200, "none", "", {redirect="/"}
            elseif not (serverCfg.pages[head.path] == nil) then
                local f = fs.open("/home/www/" .. serverCfg.pages[head.path], "r")
                if not f then
                    return 500, 'text/plain', 'Could not read page from file'
                end
                local page = textutils.unserialise(f.readAll())
                f.close()
                return 200, "table/rtml", page
            else
                return 404, "text/plain", "Page not found"
            end
        else
            return 404, "text/plain", "Invalid method, must be GET"
        end
    end)
else
    rttp.handleMsg(function(method, head, body, msg)
        print("Recived RTTP request")
        print("- " .. rttp.stringMessage(msg))
        if method ~= "GET" then
            return rttp.responseCodes.methodNotAllowed, "text/plain", "Only GET is implemented on this server, can not use '"..method.."'"
        end
        if head.path == "" then
            return rttp.responseCodes.okay, "text/plain", "This is a simple RTTP server"
        else
            return rttp.responseCodes.notFound, "text/plain", "Path not found on server"
        end
        return rttp.responseCodes.internalServerError, "text/plain", "The server encountered an error prossesing the request"
    end)
end

net.setup()
print("Starting RTTP server at "..net.ipFormat(net.getIP())..":10080")
rttp.runServer()