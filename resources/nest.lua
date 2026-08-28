---@meta

---@class System
---
---@field aur boolean
---@field arch string
---@field bootloader string
---@field hostname string
---@field locale string
---@field timezone string
---
---@field kernels string[]
---@field services string[]
---@field pkgs string[]
---
---@field pkg_sets Sets
---@field sources Repo[]
---@field users User[]

---@class Sets
---@field core boolean
---@field systemd boolean
---@field sys_utils boolean
---@field net_utils boolean
---@field archive_utils boolean

---@class Repo
---@field [1] string Repo name
---@field priority integer
---@field mirrors string[]

---@class User
---@field [1] string User name
---@field home string
---@field groups string[]
---@field pkgs string[]

---@type System
system = {}
