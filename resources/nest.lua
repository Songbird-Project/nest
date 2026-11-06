-- SPDX-FileCopyrightText: 2025-2026 Songbird Project
--
-- SPDX-License-Identifier: BSD-3-Clause

---@meta nest

-----------
-- nest --
-----------

---@class nest.AutoClean
---@field enabled? boolean
---@field when? string
---@field keep? integer

---@class nest.Nest
---@field autoclean? nest.AutoClean
nest = {}

---@param path string
---@return string[]
function nest.readlines(path) end

---------
-- pkg --
---------

---@class nest.Source
---@field enabled? boolean
---@field priority? integer
---@field mirrors? string[]

---@class nest.Source.Aur
---@field enabled? boolean

---@class nest.Source.Pkgbuild
---@field enabled? boolean
---@field source? string

---@class nest.Source.System
---@field mirrors? string[]

---@class nest.Sources
---@field aur? nest.Source.Aur
---@field luabuild? nest.Source.Luabuild
---@field system? nest.Source.System
---@field galaxy? nest.Source
---@field lib32? nest.Source
---@field custom table<string, nest.Source>

---@class nest.Pkgs
---@field repo? string[]
---@field aur? string[]
---@field pkgbuild? string[]

---@class nest.Pkg
---@field sources nest.Sources
---@field pkgs nest.Pkgs

---@type nest.Pkg
pkg = {}

---------------------
-- system.services --
---------------------

---@class nest.SvScopes
---@field system? string[]
---@field users? table<string, string[]>

---@class nest.Services
---@field manager "systemd" Other init systems are planned for support such as dinit and openrc
---@field enable? nest.SvScopes
---@field disable? nest.SvScopes
---@field mask? nest.SvScopes

------------------
-- system.users --
------------------

---@class nest.User
---@field system? boolean
---@field home? string
---@field create_home? boolean
---@field extra_groups? string[]
---@field shell? string

-----------------
-- system.boot --
-----------------

---@alias nest.Bootloader "grub" Other bootloaders are planned for support such as limine and systemd-boot

---@class nest.Boot
---@field loader? nest.Bootloader
---@field kernels? string[]
---@field timeout? integer

-----------------
-- system.info --
-----------------

---@class nest.Info
---@field locale? string
---@field hostname? string
---@field timezone? string

------------------
-- system.files --
------------------

---@class nest.File
---@field source string
---@field mode? "copy"|"symlink"|"hardlink"
---@field owner? string
---@field parents? boolean

------------
-- system --
------------

---@class nest.System
---@field enable? boolean
---@field services nest.Services
---@field users? table<string, nest.User>
---@field boot? nest.Boot
---@field info? nest.Info
---@field files? table<string, nest.File>
system = {}
