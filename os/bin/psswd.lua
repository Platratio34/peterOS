local parser = pos.Parser()
parser:addFlag('help','h')

local args, flags = parser:parse({ ... })

if flags.help then
    print('Command: passwd [options] [username]')
    print('Options:')
    print(' -help, -h | Command help')
    return
end

local username = args[1]
local cPass = nil
local nPass = nil
if not user.isSu() then
    print("Current password for " .. username .. ':')
    cPass = read('')
end

print('New password for ' .. username .. ':')
nPass = read('')
print('Re-enter new password for ' .. username .. ':')
local nPass2 = read('')

if nPass ~= nPass2 then
    printError('New passwords did not match')
    return
end

if not user.changePassword(username, cPass, nPass) then
    printError('Could not change password for ' .. username)
    return
end

print('Password for ' .. username .. ' changed')