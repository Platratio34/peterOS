---@meta

---@alias Wlan.Message.Method
---| 'msg'
---| 'advert'
---| 'connect'
---| 'disconnect'

---@class Wlan.Message
---@field ssid string
---@field dest string?
---@field method Wlan.Message.Method
---@field msg table|string|number[]
---@field sig number[]?

---@class Wlan.Network
---@field ssid string
---@field authMode 'none'|'pass'
---@field authKey string|nil
---@field channel integer
---@field publicKey byteArray|string

--[[

Network:



]]