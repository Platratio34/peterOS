if user.isSu() then
    user.sudo("")
    print("Logged out of root")
    return
end

if user.getUser() then
    local user = user.getUser()
    print("Logged out of "..user)
    user.changeUser('')
end

if not fs.exists('/user.cfg') then
    return
end
local userCfgFile = fs.open('/user.cfg', 'r')
---@diagnostic disable-next-line: need-check-nil
local userCfg = textutils.unserialiseJSON(userCfgFile.readAll())
---@diagnostic disable-next-line: need-check-nil
userCfgFile.close()
local requireLogin = userCfg.requireLogin

while requireLogin do
    print('')
    write('Enter user name: ')
    local username = read()
    print()
    write('Password for ' .. username .. ': ')
    local password = read('')
    if user.changeUser(username, password) then
        requireLogin = false
        log:info('User %s logged in', username)
        print('Welcome ' .. username)
    else
        log:warn('Failed login for user %s', username)
        printError('Invalid user or password')
    end
end