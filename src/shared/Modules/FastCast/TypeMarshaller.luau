--!nocheck
-- ^ change to strict to crash studio c:

local oldtypeof = typeof
local function typeof(objIn: any): string
	local objType = oldtypeof(objIn)
	if objType ~= "table" then
		return objType
	end

	-- Could be a custom type if it's a table.
	local meta = getmetatable(objIn)
	if oldtypeof(meta) ~= "table" then
		return objType
	end

	-- Has a metatable that's an exposed table.
	local customType: string? = meta["__type"] -- I want to mandate that this is a string.
	if customType == nil then
		return objType
	end

	-- Has a type field
	return customType
end

return typeof
