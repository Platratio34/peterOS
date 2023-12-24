---@diagnostic disable: need-check-nil
local rttp = pos.require("rttp")
local client = rttp.client
local tblStore = pos.require("tblStore")

local bkmFileName = "home/appdata/browser/bookmarks.lua"
local bkmFileMod = "home.appdata.browser.bookmarks"

local args = {...}

local links = {}
local w, h = term.getSize()
local url = ""
local back = {}
local editURL = false

local reqWait = false

local f = fs.open("/home/pmgLog/browser.log", "w")
f.write("")
f.close()

local function log(msg)
    local lf = fs.open("/home/pmgLog/browser.log", "a")
    lf.write(msg.."\n")
    lf.close()
end

local function drawBar()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.gray)
    term.clearLine()

    term.setTextColor(colors.lightGray)
    if reqWait then
        term.write("< O|")
    else
        term.write("< *|")
    end

    term.setCursorPos(5, 1)
    term.setTextColor(colors.white)
    term.write(url)
    if(editURL) then
        term.setCursorBlink(true)
        term.setTextColor(colors.lightGray)
        term.write("_")
    else
        term.setCursorBlink(false)
    end

    term.setCursorPos(w-4, 1)
    term.setTextColor(colors.lightGray)
    term.write("+ X")
    term.setCursorPos(w, 1)
    term.setTextColor(colors.red)
    term.write("X")

    term.setBackgroundColor(colors.black)

    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
end

local function display(msg)
    term.setBackgroundColor(colors.black)
    term.clear()
    links = {}

    log(msg.header.contentType)
    if msg.header.contentType == "table/rtml" then
        log("Displaying rtml")
        local body = msg.body
        log("Body length "..#body)
        for i=1,#body do
            local el = body[i]

            if not el then

            elseif el.type == "TEXT" then
                term.setCursorPos(el.x, el.y+1)
                term.setTextColor(el.color)
                term.write(el.text)
            elseif el.type == "LINK" or el.type == "DOM-LINK" then
                local lnk = {
                    x=el.x,
                    y=el.y+1,
                    w=string.len(el.text),
                    href=el.href,
                    type = el.type
                }
                table.insert(links, lnk)
                term.setCursorPos(el.x, el.y+1)
                term.setTextColor(colors.lightBlue)
                term.setBackgroundColor(colors.gray)
                term.write(el.text)
            end
        end
    elseif msg.header.contentType == "text/plain" then
        local lines = {}
        local body = msg.body
        while string.len(body) > w do
            table.insert(lines, string.sub(body,1,w))
            body = string.sub(body, w+1, -1)
        end
        table.insert(lines, body)

        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.black)
        for i=1,#lines do
            term.setCursorPos(1,i+1)
            term.write(lines[i])
        end
    end

    drawBar()

    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
end

-- local function splitURL(url)
--     local ind = string.find(url, "/")
--     local d, p = "", ""
--     if ind==nil then
--         d = url
--     else
--         d = string.sub(url, 1, ind-1)
--         p = string.sub(url, ind, -1)
--     end
--     return d, p
-- end

local function keyToChar(key)
    if string.len(keys.getName(key))==1 then
        return keys.getName(key)
    elseif key == keys.period then
        return "."
    elseif key == keys.slash then
        return "/"
    elseif key == keys.minus then
        return "-"
    elseif key == keys.underscore then
        return "_"
    elseif key == keys.one then
        return "1"
    elseif key == keys.two then
        return "2"
    elseif key == keys.three then
        return "3"
    elseif key == keys.four then
        return "4"
    elseif key == keys.five then
        return "5"
    elseif key == keys.six then
        return "6"
    elseif key == keys.seven then
        return "7"
    elseif key == keys.eight then
        return "8"
    elseif key == keys.nine then
        return "9"
    elseif key == keys.zero then
        return "0"
    end
    return ""
end

client.setup("top")

if not fs.exists(bkmFileName) then
    if not fs.exists("home/appdata") then fs.makeDir("home/appdata") end
    if not fs.exists("home/appdata/browser") then fs.makeDir("home/appdata/browser") end
    local bkf = fs.open(bkmFileName, "w")
    bkf.write("return {}")
    bkf.close()
end

local domain = ""
local path = ""
if #args == 1 then
    _, domain, path = net.splitURL(args[1])
elseif #args == 2 then
    domain = args[1]
    path = args[2]
else
    editURL = true
end

-- print("Seding request to "..domain.." "..path)

while true do
    local msg = pos.require("os.bin.rttpBrowse-home")
    if not (domain == "") then
        reqWait = true
        drawBar()
        msg = client.getSync(domain, path)
        reqWait = false
        table.insert(back, {domain, path})
    end

    if msg == nil then
        -- print("Somthing went wrong")
        -- return
        msg = {
            header={contentType="table/rtml"},
            body={
                {type="TEXT", x=(w-19)/2, y=h/2, text="Somthing Went Wrong", color=colors.red}
            }
        }
    end

    if msg == "timeout" then
        -- print("Somthing went wrong")
        -- return
        msg = {
            header={contentType="table/rtml"},
            body={
                {type="TEXT", x=(w-15)/2, y=h/2, text="Request Timeout", color=colors.red}
            }
        }
    end

    if msg.header.redirect then
        path = msg.header.redirect
        if #back > 0 then
            back[#back] = {domain, path}
        end
    else
        url = domain..path
        display(msg)
        local link = nil
        while not link do
            local event = { os.pullEvent() }
            
            if event[1] == "mouse_click" then
                local eventN, button, x, y = unpack(event)

                if y == 1 then
                    if x == w then
                        term.clear()
                        term.setCursorPos(1,1)
                        return
                    elseif x == w-2 then
                        domain = ""
                        path = ""
                        drawBar()
                        break
                    elseif x == w-4 then
                        local bkms = tblStore.loadF(bkmFileName)
                        local ex = false
                        for i=1,#bkms do
                            if bkms[i].href == url then
                                ex = true
                            end
                        end
                        if not ex then
                            table.insert(bkms, {name=url, href=url})
                            tblStore.saveF(bkms, bkmFileName)
                        end
                    elseif x == 1 then
                        if #back > 0 then
                            local b = table.remove(back)
                            domain = b[1]
                            path = b[2]
                            drawBar()
                            break
                        end
                    elseif x == 3 then
                        break
                    else
                        editURL = true
                        drawBar()
                    end
                else
                    editURL = false
                    for i=1,#links do
                        local lnk = links[i]
                        if x>=lnk.x and x<lnk.x+lnk.w and y==lnk.y then
                            link = lnk
                            break
                        end
                    end
                end
            elseif event[1]=="key" then
                local eventN, key, hold = unpack(event)
                local kN = keys.getName(key)
                if editURL then
                    if key == keys.backspace then
                        url = string.sub(url, 1, -2)
                    elseif key == keys.enter or key == keys.numPadEnter then
                        _, domain, path = net. splitURL(url)
                        editURL = false
                        drawBar()
                        break
                    else
                        url = url..keyToChar(key)
                    end
                    drawBar()
                end
            end
        end
        if link then
            if link.type == "DOM-LINK" then
                _, domain, path = net.splitURL(link.href)
            else
                path = link.href
            end
        end
    end
end