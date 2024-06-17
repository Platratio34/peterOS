local parser = pos.Parser()
parser:addFlag('user', 'u')

local args, flags = parser:parse({...})

write("Password: ")
local psw = read("")
if flags.user then
    if user.changeUser(flags.user, psw) then
        print('Switched to '..flags.user)
    else
        printError("Invalid Password")
    end
else
    if user.sudo(psw) then
        print("Logged in as root")
    else
        printError("Invalid Password")
    end
end
