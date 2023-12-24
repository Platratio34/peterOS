local function send(modem, origin, host, path, method, code, body, headers)
    -- print(origin.." "..host)
    local msg = {
        type = "rttp",
        origin = origin,
        host = host,
        path = path,
        method = method,
        code = code,
        body = body,
        header = headers
    }
    -- print("Sending message: ")
    -- for k,v in pairs(msg) do
    --     print("  "..k.." = "..tostring(v))
    -- end
    modem.transmit(80, 80, msg)
end

return {send = send}