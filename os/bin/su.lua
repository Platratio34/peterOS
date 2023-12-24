local args = {...}

write("Password: ")
local psw = read("")
if user.sudo(psw) then
    print("Logged in as root")
else
    printError("Invalid Password")
end
