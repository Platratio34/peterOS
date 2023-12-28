---@package rttp

local expect = require "cc.expect"

-- +-----------------------+
-- | RTTP Library          |
-- | Made by Peter Crall   |
-- | Loosely based on HTTP |
-- +-----------------------+

---Library of RTTP related functions
_G.rttp = {}

-- +----------------+
-- | Base Functions |
-- +----------------+

---Send an RTTP message, returns the message ID of the send message
---@param dest string|integer Destination hostname, IP Address, HW Address
---@param path string URI path
---@param method string Method (GET, POST)
---@param contentType string Content type (none, text/plain, table/rtml, ...)
---@param body any Message body
---@param cookies nil|table Optional. Cookie table
---@return integer id Message Id
rttp.send = function(dest, path, method, contentType, body, cookies)
    expect(1, dest, "string", "number")
    expect(2, path, "string")
    expect(3, method, "string")
    expect(4, contentType, "string")
    expect(5, body, "string", "number", "table")

    local head = {
        type = "rttp",
        method = method,
        contentType = contentType,
        path = path,
        cookies = cookies
    }
    return net.sendAdv(10080, dest, head, body)
end
---Send an RTTP message, and await the response with a 2 second timeout
---@param dest string|integer Destination hostname, IP Address, HW Address
---@param path string URI path
---@param method string Method (GET, POST)
---@param contentType string Content type (none, <code>text/plain</code>, <code>table/rtml</code>, ...)
---@param body any Message body
---@param cookies nil|table Optional. Cookie table
---@param timeout nil|number Reply timeout in seconds (default is 2 seconds, set to -1 to disable)
---@return string|RttpMessage rsp Response message, or error string
rttp.sendSync = function(dest, path, method, contentType, body, cookies, timeout)
    expect(1, dest, "string", "number")
    expect(2, path, "string")
    expect(3, method, "string")
    expect(4, contentType, "string")
    expect(5, body, "string", "number", "table")

    local head = {
        type = "rttp",
        method = method,
        contentType = contentType,
        path = path,
        cookies = cookies
    }
    local msg = net.sendAdvSync(10080, dest, head, body, timeout)
    ---@cast msg RttpMessage
    return msg
end

---Reply to an RTTP message (intended for server)
---@param msg RttpMessage Message to reply to
---@param code integer Response Code (see rttp.responseCodes)
---@param contentType string Content type (none, text/plain, table/rtml, ...)
---@param body any Message body
---@param head RttpMessage.Header|nil Message head
---@return integer id Message Id
rttp.reply = function(msg, code, contentType, body, head)
    expect(1, msg, "table")
    expect(2, code, "number")
    expect(3, contentType, "string")
    expect(4, body, "string", "number", "table")
    expect(5, head, "table", "nil")
    if head == nil then
        ---@diagnostic disable-next-line: missing-fields
        head = {}
    end
    head.type = "rttp"
    head.method = msg.method
    head.contentType = contentType
    head.code = code
    head.rspDomain = msg.domain

    return net.reply(10080, msg, head, body)
end

---Check if a net message is a valid RTTP message
---@param message table Message to check
---@return boolean valid If message was valid RTTP
rttp.valid = function(message)
    expect(1, message, "table")

    if message.port ~= 10080 then return false end
    if message.header.type ~= "rttp" then return false end
    return true
end

---Wait for a RTTP message with a timeout.
---@param timeout number Timeout in seconds, <0 to disable (optional, defaults to 2)
---@return string|RttpMessage rsp Response message, or error string
rttp.waitForMsg = function(timeout)
    expect(1, timeout, "number")

    if timeout == nil then timeout = 2 end
    local msg = net.waitForMsgAdv(10080, timeout, rttp.valid)
    ---@cast msg RttpMessage
    return msg
end

-- +---------------------+
-- | RTTP Response Codes |
-- +---------------------+

---RTTP response codes by name
rttp.responseCodes = {
    switchingProtocols = 101, -- Switch protocol to the one indicated in <code type=var>header.upgrade</code>
    okay = 200, -- Request processed okay
    noContent = 204, -- No content, only header change
    movedPermanently = 301, -- Page has PERMANENTLY moved to <code type=var>header.redirect</code>
    movedTemporarily = 307, -- Page has TEMPORARILY moved to <code type=var>header.redirect</code>
    seeOther = 303, -- Go see this other page, then you can return here
    badRequest = 400, -- Bad request formatting, or missing parameters
    unauthorized = 401, -- Client should authenticate first
    forbidden = 403, -- Client does not have access
    notFound = 404, -- Requested content was not found on the server
    methodNotAllowed = 405, -- The requested method was not allowed
    imATeapot = 418, -- The server refuses the attempt to brew coffee with a teapot
    failedDependency = 424, -- Dependency was not present for request
    upgradeRequired = 426, -- Request must be performed with encrypted messages
    internalServerError = 500, -- Server encountered an internal error processing the request
    notImplemented = 501, -- The request is not yet implemented
    serviceUnavailable = 503, -- The requested service is not ready to handel the request
}

---Get the name of a response code by number
---@param code integer RTTP response code
---@return string code Name of response code
rttp.codeName = function(code)
    expect(1, code, "number")

    if code == 101 then return "Switching Protocols"
    elseif code == 200 then return "Okay"
    elseif code == 204 then return "No Content"
    elseif code == 301 then return "Moved Permanently"
    elseif code == 302 then return "Moved Temporarily"
    elseif code == 303 then return "See Other"
    elseif code == 400 then return "Bad Request"
    elseif code == 401 then return "Unauthorized"
    elseif code == 403 then return "Forbidden"
    elseif code == 404 then return "Not Found"
    elseif code == 405 then return "Method Not Allowed"
    elseif code == 418 then return "I'm a teapot"
    elseif code == 424 then return "Failed Dependency"
    elseif code == 426 then return "Upgrade Required"
    elseif code == 500 then return "Internal Server Error"
    elseif code == 501 then return "Not Implemented"
    elseif code == 503 then return "Service Unavailable"
    else return "Unknown"
    end
end

---Returns a string representation of an RTTP message
---@param msg RttpMessage Message to serialize
---@return string message String version of message
rttp.stringMessage = function(msg)
    expect(1, msg, "table")
    if msg.header.type ~= "rttp" and msg.header.type "rttps" then
        return "Unknown message type"
    end
    local str = ""
    if msg.header.rspDomain then
        str = str..msg.header.rspDomain
    else
        str = str..net.ipFormat(msg.origin)
    end
    str = str .. " -> "
    if msg.header.domain then
        str = str..msg.header.domain
    else
        str = str..net.ipFormat(msg.dest)
    end
    str = str .. msg.header.path.." | "
    str = str .. msg.header.method .. ", "
    str = str .. msg.header.contentType
    str = str .. " | "
    str = str .. textutils.serialise(msg.body)
    return str
end

-- +-----------------------+
-- | RTTP Server Functions |
-- +-----------------------+

---Server message handler function.
---@param method string RTTP method of request
---@param head RttpMessage.Header Message header table
---@param body any Message body
---@param msg RttpMessage Full message table
---@return integer code RTTP Response code
---@return string contentType Reply body content type
---@return any body Reply body
---@return RttpMessage.Header|nil head Optional. Message header
local msgHandler = function(method, head, body, msg)
    return rttp.responseCodes.internalServerError, "text/plain", "Message handler not set"
end

---Set the server message handler.
---Function takes in the method (<code class=type>string</code>), header (<code class=type>table</code>), body (<code class=type>any</code>), and the raw message (<code class=type>RttpMessage</code>).
---Function should return the code (<code class=type>number</code>), content type (<code class=type>string</code>), and the body (any not nil).
---@param func function Server message handler function
rttp.handleMsg = function(func)
    expect(1, func, "function")
    msgHandler = func
end

-- Loop for server
local function serverLoop()
    local msg = rttp.waitForMsg(-1)
    if type(msg) == "table" then
        local suc, code, cType, body, head = pcall(msgHandler, msg.header.method, msg.header, msg.body, msg)
        if (not suc) or type(code) ~= "number" or type(cType) ~= "string" or type(body) == "nil" then
            if not suc then
                printError("ERROR: "..code)
            end
            code = rttp.responseCodes.internalServerError
            cType = "text/plain"
            body = "Something went wrong processing the request"
            print("Internal error on "..rttp.stringMessage(msg))
        end
        rttp.reply(msg, code, cType, body, head)
    end
end
---Run the server handling messages with the function set with rttp.handleMsg(func)
rttp.runServer = function()
    if not net.setup() then
        error("Network setup failed, server not started", 0)
        return
    end
    net.open(10080)
    while true do
        serverLoop()
    end
end
local handlerId = -1
---Registers server message handler, starting a non-blocking server
---@return boolean success Returns True unless server has already been started
function rttp.registerHandler()
    if handlerId ~= -1 then
        return false
    end
    handlerId = net.registerMsgHandler(function(msg)
        if not rttp.valid(msg) then return end
        ---@cast msg RttpMessage

        local suc, code, cType, body, head = pcall(msgHandler, msg.header.method, msg.header, msg.body, msg)
        if (not suc) or type(code) ~= "number" or type(cType) ~= "string" or type(body) == "nil" then
            if not suc then
                print("ERROR: "..code)
            end
            code = rttp.responseCodes.internalServerError
            cType = "text/plain"
            body = "Something went wrong processing the request"
            print("Internal error on "..rttp.stringMessage(msg))
        end
        rttp.reply(msg, code, cType, body, head)
    end)
    return true
end


---Sends a GET message
---@param dest string|integer Destination hostname, IP address, or HW address
---@param path string URI path
---@param cookies nil|table Optional. Cookie table
---@return integer id Message Id
rttp.get = function(dest, path, cookies)
    return rttp.send(dest, path, "GET", "none", {}, cookies)
end
---Sends a GET message and wait for response
---@param dest string|integer Destination hostname, IP address, or HW address
---@param path string URI path
---@param cookies nil|table Optional. Cookie table
---@param timeout nil|number Reply timeout in seconds (default is 2 seconds, set to -1 to disable)
---@return string|RttpMessage rsp Response message, or error string
rttp.getSync = function(dest, path, cookies, timeout)
    return rttp.sendSync(dest, path, "GET", "none", {}, cookies, timeout)
end
---Sends a POST message
---@param dest string|integer Destination hostname, IP address, or HW address
---@param path string URI path
---@param cType string Content type (none, text/plain, table/rtml, ...)
---@param body any Message body
---@param cookies nil|table Optional. Cookie table
---@return integer id Message Id
rttp.post = function(dest, path, cType, body, cookies)
    return rttp.send(dest, path, "POST", cType, body, cookies)
end
---Sends a POST message and wait for response
---@param dest string|integer Destination hostname, IP address, or HW address
---@param path string URI path
---@param cType string Content type (none, text/plain, table/rtml, ...)
---@param body any Message body
---@param cookies nil|table Optional. Cookie table
---@param timeout nil|number Reply timeout in seconds (default is 2 seconds, set to -1 to disable)
---@return string|RttpMessage rsp Response message, or error string
rttp.postSync = function(dest, path, cType, body, cookies, timeout)
    return rttp.sendSync(dest, path, "POST", cType, body, cookies, timeout)
end

---@class RttpMessage : NetMessage RTTP message struct
---@field header RttpMessage.Header Message header table

---@class RttpMessage.Header : NetMessage.Header RTTP message header table
---@field method string|nil Request Only. RTTP method one of: <code>GET</code>, <code>POST</code>, or other HTTP request methods
---@field path string|nil Request Only. URI path
---@field domain string|nil Request Only. Destination domain
---@field code number|nil Response Only. RTTP response code
---@field rspDomain string|nil Response Only. Domain request was sent to
---@field contentType string|nil Content type of body of <code>POST</code> or response
---@field upgrade boolean|nil Optional. Response Only. Protocol to upgrade to on code <code>101</code> or <code>426</code>
---@field redirect string|nil Optional. Response Only. Redirect location for codes <code>301</code> and <code>307</code>
---@field cookies {str: str}|nil Optional. Cookie table