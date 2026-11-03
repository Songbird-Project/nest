-- SPDX-FileCopyrightText: NONE
--
-- SPDX-License-Identifier: Unlicense
--
-- This file was generated with the use of Claude
-- For this reason, all copyright is waived

local function prune(v)
	local t = type(v)
	if t == "function" or t == "userdata" or t == "thread" then
		return nil
	end
	if t ~= "table" then
		return v
	end

	local out = {}
	for k, x in pairs(v) do
		local p = prune(x)
		if p ~= nil and not (type(p) == "table" and next(p) == nil) then
			out[k] = p
		end
	end
	return out
end

return json.encode(prune({ nest = nest, pkg = pkg, system = system }))
