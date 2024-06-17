local parser = pos.Parser()

local args, flags = parser:parse({ ... })

local username = args[1]

if fs.exists('/' .. username .. '.userDat') then
    error('User with name ' .. username .. ' already exists')
end

print('Enter password for new user:')
local password = read('')

if not user.newUser(username, password) then
    error("Unable to make new user")
end
print('New user with name '..username..'created')