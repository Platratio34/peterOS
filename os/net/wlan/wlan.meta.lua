---@meta

---@alias Wlan.Message.Method
---| 'msg' Standard WLAN wrapped message
---| 'advert' Network advertisement message. *Broadcast*
---| 'connect' Network connect message. Also confirms connection
---| 'disconnect' Network disconnect message. Only body is HW address, must be encrypted
---| 'query' Network query message. *Broadcast*
---| 'register-ip' Registers an IP address for the device

---@class Wlan.Message WLAN message structure
---@field ssid string SSID of the network the message is sent on
---@field dest string? **From AP only** Destination HW address of the message
---@field origin string? **To AP only** Origin HW address of the message
---@field method Wlan.Message.Method Message method
---@field body table|string|byteArray Message body. If encrypted, must have `sig` field
---@field sig byteArray? Signature of the message if encrypted

---@class Wlan.Network
---@field ssid string
---@field authMode 'none'|'key'
---@field authKey string|nil
---@field channel integer
---@field publicKey byteArray|string

---@class Wlan.AdvertMessage : Wlan.Message
---@field body Wlan.Network

---@class Wlan.ConnectBody
---@field publicKey byteArray Public key of the connecting device
---@field authKey byteArray? Encrypted authentication key

---@class Wlan.ConnectReturnBody
---@field valid boolean
---@field reason string?

---@class Wlan.QueryBody
---@field publicKey byteArray Public key of the querying device

---@class Wlan.QueryReturnMessage : Wlan.Message
---@field body Wlan.Network

---@class Wlan.RegisterIPBody
---@field addr NetAddress? Address to register for the device. If absent, will only update broadcast
---@field remove boolean? Un register the address for the device
---@field broadcast boolean? If the broadcast messages should be passed to it as well. If unset will have no effect

--[[

Network:



]]