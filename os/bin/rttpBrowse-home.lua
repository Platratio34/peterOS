local w, h = term.getSize()

local home = {
    header={contentType="table/rtml"},
    body={
        {type="TEXT", x=(w-23)/2, y=h/2, text="Welcome to RTTP Browser", color=colors.green}
    }
}

local f = fs.open("home/appdata/browser/bookmarks.lua", "r")
local bkms = {}
if f then
    bkms = textutils.unserialise(f.readAll())
    f.close()
end

local x, y = 1, 1
print(#bkms)
for i=1,#bkms do
    local bkm = bkms[i]
    local l = string.len(bkm.name)
    if x+l > w then
        x = 1
        y = y+1
    end
    local lnk = {
        type="DOM-LINK",
        x=x,
        y=y,
        text=bkm.name,
        href=bkm.href
    }
    table.insert(home.body, lnk)
    x = x+1+l
end

return home