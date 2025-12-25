local replicatedStorage = game:GetService("ReplicatedStorage")
local config = require(replicatedStorage.SPH_Assets.GameConfig)
local destructionSounds = replicatedStorage.SPH_Assets.Sounds.Destruction
local module = {}

local function PlaySoundAtLocation(position, soundName)
	local sound = destructionSounds:FindFirstChild(soundName)
	if sound then
		local newAttachment = Instance.new("Attachment", workspace.Terrain)
		newAttachment.Name = "TempDestructionSound"
		newAttachment.WorldPosition = position

		local newSound = sound:Clone()
		newSound.Parent = newAttachment
		newSound:Play()

		task.delay(newSound.TimeLength, function()
			newAttachment:Destroy()
		end)
	end
end

module.DestroyObject = function(object: Model, player)
	object:SetAttribute("Destroyed", true)

	local destructionType = object:GetAttribute("DestructionType")
	local model = object:IsA("Model")
	local destructionSound = object:GetAttribute("DestructionSound")

	if model then -- Destroy a whole model
		for _, desc in object:GetDescendants() do
			if desc:IsA("BasePart") then
				local part = desc
				part.Anchored = false
				part.CollisionGroup = "Debris" -- Won't collide with players, guns, or casings

				for _, joint: JointInstance in part:GetJoints() do
					joint.Enabled = false
				end

				for _, child in part:GetChildren() do
					if child:IsA("Constraint") then
						child.Enabled = false
					end
				end

				if player then
					part:SetNetworkOwner(player)
				end
			elseif desc:IsA("Constraint") or desc:IsA("JointInstance") then
				desc.Enabled = false
			end
		end

		if destructionSound then
			local soundPosition
			if object.PrimaryPart then
				soundPosition = object.PrimaryPart.Position
			else
				soundPosition = object.WorldPivot.Position
			end
			PlaySoundAtLocation(soundPosition, destructionSound)
		end
	else -- "Destroy" this part
		local part: BasePart = object
		part.Anchored = false
		part.CollisionGroup = "Debris" -- Won't collide with players, guns, or casings

		for _, joint: JointInstance in part:GetJoints() do
			joint.Enabled = false
		end

		for _, child in part:GetChildren() do
			if child:IsA("Constraint") then
				child.Enabled = false
			end
		end

		if player then
			part:SetNetworkOwner(player)
		end

		if destructionSound then
			PlaySoundAtLocation(part.Position, destructionSound)
		end
	end

	-- Destruction type effects
	if destructionType == "Instant" then -- Instantly destroy object
		object:Destroy()
	elseif destructionType == "Explosion" then -- Create an explosion and destroy object
		local explosionType = object:GetAttribute("ExplosionType") or "Default"
		local explosionOrigin = object:IsA("Model") and object:GetPivot().Position or object.Position
		local explosionRadius = object:GetAttribute("ExplosionRadius") or 20
		local CreateExplosion = require(replicatedStorage.SPH_Assets.Modules.ExplosionFX)
		object:Destroy()
		CreateExplosion(explosionOrigin, explosionRadius, explosionType, player)
	else -- "Default" behavior
		task.delay(config.destructibleDespawnTime, function()
			object:Destroy()
		end)
	end
end

return module
