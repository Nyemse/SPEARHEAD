--!nocheck
-- shut up jesser

--[[
	To use: local table = require(this)
	(Yes, override table.)

	Written by EtiTheSpirit. Adds custom functions to the `table` value provided by roblox (in normal cases, this would simply modify `table`, but Roblox has disabled that so we need to use a proxy)
	
	CHANGES:
		3 December 2019 @ 11:07 PM CST:
			+ Added table.join
			
			
		21 November 2019 @ 6:50 PM CST:
			+ Added new method bodies to skip/take using Luau's new methods. Drastic speed increases achieved. CREDITS: Halalaluyafail3 (See https://devforum.roblox.com/t/sandboxed-table-system-add-custom-methods-to-table/391177/12?u=etithespirit)
			+ Added table.retrieve as proposed by ^ under the name "table.range" as this name relays what it does a bit better, I think.
			+ Added table.skipAndTake as an alias method.

--]]

local RNG = Random.new()
local RobloxTable = table
local Table = {}

-- Returns true if the table contains the specified value.
Table.contains = function(tbl, value)
	return Table.indexOf(tbl, value) ~= nil -- This is kind of cheatsy but it promises the best performance.
end

-- A combo of table.find and table.keyOf -- This first attempts to find the ordinal index of your value, then attempts to find the lookup key if it can't find an ordinal index.
Table.indexOf = function(tbl, value)
	local fromFind = table.find(tbl, value)
	if fromFind then
		return fromFind
	end

	return Table.keyOf(tbl, value)
end

-- Returns the key of the specified value, or nil if it could not be found. Unlike IndexOf, this searches every key in the table, not just ordinal indices (arrays)
-- This is inherently slower due to how lookups work, so if your table is structured like an array, use table.find
Table.keyOf = function(tbl, value)
	for index, obj in pairs(tbl) do
		if obj == value then
			return index
		end
	end
	return nil
end

-- Only works on ordinal. yada yada.
Table.insertAndGetIndexOf = function(tbl, value)
	tbl[#tbl + 1] = value
	return #tbl
end

-- ONLY SUPPORTS ORDINAL TABLES (ARRAYS). Skips *n* objects in the table, and returns a new table that contains indices (n + 1) to (end of table)
Table.skip = function(tbl, n)
	return table.move(tbl, n + 1, #tbl, 1, table.create(#tbl - n))
end

-- ONLY SUPPORTS ORDINAL TABLES (ARRAYS). Takes *n* objects from a table and returns a new table only containing those objects.
Table.take = function(tbl, n)
	return table.move(tbl, 1, n, 1, table.create(n))
end

-- ONLY SUPPORTS ORDINAL TABLES (ARRAYS). Takes the range of entries in this table in the range [start, finish] and returns that range as a table.
Table.range = function(tbl, start, finish)
	return table.move(tbl, start, finish, 1, table.create(finish - start + 1))
end

-- ONLY SUPPORTS ORDINAL TABLES (ARRAYS). An alias that calls table.skip(skip), and then takes [take] entries from the resulting table.
Table.skipAndTake = function(tbl, skip, take)
	return table.move(tbl, skip + 1, skip + take, 1, table.create(take))
end

-- ONLY SUPPORTS ORDINAL TABLES (ARRAYS). Selects a random object out of tbl
Table.random = function(tbl)
	return tbl[RNG:NextInteger(1, #tbl)]
end

-- ONLY SUPPORTS ORDINAL TABLES (ARRAYS). Merges tbl0 and tbl1 together.
Table.join = function(tbl0, tbl1)
	local nt = table.create(#tbl0 + #tbl1)
	local t2 = table.move(tbl0, 1, #tbl0, 1, nt)
	return table.move(tbl1, 1, #tbl1, #tbl0 + 1, nt)
end

-- ONLY SUPPORTS ORDINAL TABLES (ARRAYS). Removes the specified object from this array.
Table.removeObject = function(tbl, obj)
	local index = Table.indexOf(tbl, obj)
	if index then
		table.remove(tbl, index)
	end
end

return setmetatable({}, {
	__index = function(tbl, index)
		if Table[index] ~= nil then
			return Table[index]
		else
			return RobloxTable[index]
		end
	end,

	__newindex = function(tbl, index, value)
		error("Add new table entries by editing the Module itself.")
	end,
})
