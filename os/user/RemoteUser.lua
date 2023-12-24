---@class RemoteUser: LocalUser pOS remote user object
---@field protected _server string Server hostname
local RemoteUser = {
    _server = '',
}
local RemoteUserMT = {
    __index = RemoteUser
}
local fsOpen, osLog, LocalUser = unpack({ ... })
local sha256 = require("hash.sha256")

setmetatable(RemoteUserMT, {__index = LocalUser})
function RemoteUserMT.__call(server, userName, pass)
    local msg = net.sendAdvSync(net.standardPorts.remoteUser, server, {
        type = 'tryLogin',
    }, {
        user = userName,
        pass = pass,
    })
    if type('msg') == 'string' then
        osLog:warn('Remote user login error: ' .. msg)
        return nil
    end
    if not msg.header.suc then
        osLog:warn('Remote user login error: ' .. msg.body.error)
        return nil
    end

    if not msg.body.user then
        return nil
    end

    local user = msg.body.user
    user._server = server
    ---@cast user RemoteUser
    setmetatable(user, RemoteUserMT)
    return user
end

---Saves the remote user to remote
---@return boolean saved
function RemoteUser:save()
    local msg = net.sendAdvSync(net.standardPorts.remoteUser, self.server, {
        type = 'tryLogin',
    }, {
        name = self.name,
        pswH = self.pswH,
        _perm = self._perm,
    })
    if type('msg') == 'string' then
        osLog:warn('Remote user save error: ' .. msg)
        return false
    end
    if not msg.header.suc then
        osLog:warn('Remote user save error: ' .. msg.body.error)
        return false
    end
    return true
end

return RemoteUser