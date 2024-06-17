if not user.isSu() then
    printError("Must be SuperUser to make a new user")
end

local parser = pos.Parser()

local args, flags = parser:parse({ ... })

local username = args[1]

if fs.exists('/' .. username .. '.userDat') then
    printError('User with name ' .. username .. ' already exists')
end

print('Enter password for new user:')
local password = read('')

if not user.newUser(username, password) then
    printError("Unable to make new user")
end
print('New user with name '..username..'created')