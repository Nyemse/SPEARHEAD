local assets = script.Parent
local callbacks = {}

-- This is called right before a new viewmodel (first person arms) is created.
-- player corresponds to the player receiving this viewmodel.
-- newViewmodel is what ViewMod will pick as their viewmodel if nothing is returned.
-- If a different WeaponRig is returned from this function, it will be used instead.
-- NOTE this is only called once when the player spawns in, this cannot be used to update the viewmodel.
callbacks.viewmodelOverride = function(player: Player, newViewmodel: Model) -- CLIENT ONLY
	--[[
	For example;
	
	if player.Name == "InabaTwi" then
		return assets.Arms.CoolArms.WeaponRig
	end
	
	--]]
	return nil
end

-- This is called when the viewmodel's appearance is updated.
-- This happens when equipping a gun or switching between first/third person.
-- Player refers to the local player, currentViewmodel refers to the player's viewmodel.
-- This can be used to update a viewmodel's appearance based on a player's clothing, equipment, etc.
-- This function does not return anything.
callbacks.onViewmodelRefresh = function(player: Player, currentViewmodel: Model) -- CLIENT ONLY
end

return callbacks
