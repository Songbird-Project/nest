---@meta

---@class SystemConfig
---@field aur boolean
---@field profile string
---@field bootloader string
---@field kernels string[]
---@field services string[]
---@field packages string[]

---@class Repo
---@field [string] string
---@field arch string
---@field mirrors string[]

---@class Profile
---@field [string] string
---@field packages string[]

---@class Nest
---@field system SystemConfig
---@field profiles Profile[]
---@field repos Repo[]

nest = {}
