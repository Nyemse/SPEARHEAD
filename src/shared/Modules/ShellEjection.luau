local debris = game:GetService("Debris")

local assets = game:GetService("ReplicatedStorage").SPH_Assets
local config = require(assets.GameConfig)
local ammoTypes = assets.Ammo
local storageFolder = workspace:WaitForChild("SPH_Workspace"):FindFirstChild("Shells")

local shells = {}

local module = {}

module.ejectShell = function(player: Player, tool, gunModel)
	local wepStats = require(tool.SPH_Weapon.WeaponStats)
	if not tool or not gunModel or not gunModel:FindFirstChild("Grip") then
		return
	end
	local origin: CFrame = gunModel.Grip:FindFirstChild("Chamber")
	if not origin then
		warn(
			tool.Name
				.. " does not have a chamber! Add an attachment named 'Chamber' to the gun's grip to resolve this issue."
		)
		return
	end
	origin = origin.WorldCFrame
	local distance = player:DistanceFromCharacter(origin.Position)
	local shellModelFolder = ammoTypes:FindFirstChild(wepStats.ammoType) or ammoTypes.Default

	if distance <= config.shellDistance then
		local newShell: BasePart = shellModelFolder.Casing:Clone()
		newShell.Anchored = false
		--newShell.CanCollide = true
		newShell.CFrame = origin
		newShell.Name = player.Name .. "_Casing_" .. tool.Name
		newShell.CastShadow = false
		newShell.CollisionGroup = "Casings"
		newShell.CollisionGroup = "Casings"
		newShell.Transparency = 1
		task.delay(0.01, function()
			newShell.Transparency = 0
		end)
		task.delay(config.shellAnchorTime or 3, function()
			newShell.Anchored = true
			newShell.CanCollide = false
		end)

		local forcePoint = newShell.ForcePoint or Instance.new("Attachment", newShell)

		local ejectionForce = Instance.new("VectorForce", newShell)
		ejectionForce.Visible = false
		ejectionForce.Force = wepStats.calcEjectionForce()
		ejectionForce.Attachment0 = forcePoint

		debris:AddItem(forcePoint, 0.001)

		-- Using a table ensures that shells stay in the order they were created
		table.insert(shells, newShell)
		if #shells > config.shellMaxCount then
			table.remove(shells, 1)
		end

		debris:AddItem(newShell, config.shellDespawn)

		newShell.Parent = storageFolder

		local listener
		listener = newShell.Touched:Connect(function(partTouched)
			if
				newShell.AssemblyLinearVelocity.Magnitude > 20
				and not partTouched:IsDescendantOf(player.Character)
				and not partTouched:IsDescendantOf(gunModel)
				and partTouched.CanCollide
			then
				local NewSound = newShell.Drop:Clone()
				NewSound.Parent = newShell
				NewSound.PlaybackSpeed = math.random(30, 50) / 40
				NewSound:Play()
				NewSound.PlayOnRemove = true
				NewSound:Destroy()
				debris:AddItem(NewSound, 2)
				listener:Disconnect()
			end
		end)
	end
end

return module
