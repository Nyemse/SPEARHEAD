-- Main server script

local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local debris = game:GetService("Debris")
local testService = game:GetService("TestService")
local proxPromptService = game:GetService("ProximityPromptService")
local collectionService = game:GetService("CollectionService")

local assets = replicatedStorage.SPH_Assets
local modules = assets.Modules
local mainui = assets.HUD.SPH_UI

local config = require(assets.GameConfig)
local warnPrefix = "[ SPEARHEAD ] "
print(warnPrefix .. "Loading Server " .. config.version)

local physicsService = game:GetService("PhysicsService")
physicsService:RegisterCollisionGroup("Casings")
physicsService:RegisterCollisionGroup("Players")
physicsService:RegisterCollisionGroup("RootParts")
physicsService:RegisterCollisionGroup("Guns")
physicsService:RegisterCollisionGroup("Debris")
physicsService:CollisionGroupSetCollidable("Casings", "Casings", false)
physicsService:CollisionGroupSetCollidable("Casings", "Players", false)
physicsService:CollisionGroupSetCollidable("Guns", "Guns", false)
physicsService:CollisionGroupSetCollidable("Guns", "Players", false)
physicsService:CollisionGroupSetCollidable("Casings", "Guns", false)
physicsService:CollisionGroupSetCollidable("RootParts", "Guns", false)
physicsService:CollisionGroupSetCollidable("RootParts", "Casings", false)
physicsService:CollisionGroupSetCollidable("Debris", "Casings", false)
physicsService:CollisionGroupSetCollidable("Debris", "Guns", false)

if config.disablePlayerDebrisCollision then
	physicsService:CollisionGroupSetCollidable("Debris", "Players", false)
	physicsService:CollisionGroupSetCollidable("Debris", "RootParts", false)
end

local weldMod = require(modules.WeldMod)
local bridgeNet = require(replicatedStorage.SPH_Assets.Modules.BridgeNet)
local viewMod = require(modules.ViewMod)
local explosionMod = require(modules.ExplosionFX)
local ragdoll = require(modules.RagdollMod)
local systemMessages = require(modules.SystemMessages)
local fractureGlass = require(modules.FractureGlass)
local objectDestruction = require(modules.ObjectDestruction)
local hitscan = require(modules.Hitscan)

local bodyAnimRequest = bridgeNet.CreateBridge("BodyAnimRequest")
local bodyAnimCommand = bridgeNet.CreateBridge("BodyAnimCommand")
local switchWeapon = bridgeNet.CreateBridge("SwitchWeapon")
local repFire = bridgeNet.CreateBridge("ReplicateFire")
local repReload = bridgeNet.CreateBridge("Reload")
local repSound = bridgeNet.CreateBridge("ReplicateSound")
local bulletHit = bridgeNet.CreateBridge("BulletHit")
local repHit = bridgeNet.CreateBridge("ReplicateHit")
local repChamber = bridgeNet.CreateBridge("PlayerChamber")
local moveBolt = bridgeNet.CreateBridge("MoveBolt")
local playerFire = bridgeNet.CreateBridge("PlayerFire")
local playSound = bridgeNet.CreateBridge("PlaySound")
local sysMessage = bridgeNet.CreateBridge("SystemMessage")
local fallDamage = bridgeNet.CreateBridge("FallDamage")
local repBolt = bridgeNet.CreateBridge("ReplicateBolt")
local switchFireMode = bridgeNet.CreateBridge("SwitchFireMode")
local repFootstep = bridgeNet.CreateBridge("ReplicateFootstep")
local playerDropGun = bridgeNet.CreateBridge("PlayerDropGun")
local playerToggleAttachment = bridgeNet.CreateBridge("PlayerToggleAttachment")
local repToggleAttachment = bridgeNet.CreateBridge("ReplicateToggleAttachment")
local repBoltOpen = bridgeNet.CreateBridge("RepBoltOpen")
local magGrab = bridgeNet.CreateBridge("MagGrab")
local repMagGrab = bridgeNet.CreateBridge("ReplicateMagGrab")
local playerLean = bridgeNet.CreateBridge("PlayerLean")
local repLean = bridgeNet.CreateBridge("ReplicateLean")

local naughtyList = {} -- Used to prevent exploiters from rejoining a server, and stopping any scripts they might be running.

local function CheckNaughtyList(playerID)
	if table.find(naughtyList, playerID) then
		return true
	end
end

local function MergeTables(table1, table2)
	return table.pack(table.unpack(table1), table.unpack(table2))
end

-- Set up ignore parts list
local ignoreParts = collectionService:GetTagged("SPH_NoCollide")
collectionService:GetInstanceAddedSignal("SPH_NoCollide"):Connect(function(newInstance)
	table.insert(ignoreParts, newInstance)
end)

game:GetService("SoundService").RespectFilteringEnabled = true -- RespectFilteringEnabled is required for the sound system

local mainFolder = Instance.new("Folder", workspace)
mainFolder.Name = "SPH_Workspace"
local projectiles = Instance.new("Folder", mainFolder)
projectiles.Name = "Projectiles"
local cache = Instance.new("Folder", mainFolder)
cache.Name = "Cache"
local bodies = Instance.new("Folder", mainFolder)
bodies.Name = "Bodies"
local shells = Instance.new("Folder", mainFolder)
shells.Name = "Shells"
local drops = Instance.new("Folder", mainFolder)
drops.Name = "Drops"

local dropTable = {}

local dropCFrame = CFrame.new(0, 1, -3)

local function HolsterWeapon(player, holsterPart, tool, holsterCFrame)
	local holsterModel
	local wepStats = require(tool.SPH_Weapon.WeaponStats)
	if not assets.WeaponModels.HolsterModels:FindFirstChild(tool.Name) then
		holsterModel = assets.WeaponModels:FindFirstChild(tool.Name):Clone()
		holsterModel.Name = "Holster_" .. tool.Name
		weldMod.WeldModel(holsterModel, holsterModel.Grip)
		local holsterWeld = weldMod.BlankWeld(holsterPart, holsterModel.Grip)
		holsterWeld.Name = "HolsterWeld"
		holsterWeld.C0 = holsterCFrame
		holsterWeld.Parent = holsterModel
		holsterModel.Parent = player.Character
	else
		holsterModel = assets.WeaponModels.HolsterModels:FindFirstChild(tool.Name):Clone()
		holsterModel.Name = "Holster_" .. tool.Name
		weldMod.WeldModel(holsterModel, holsterModel.Middle)
		local holsterWeld = weldMod.BlankWeld(holsterPart, holsterModel.Middle)
		holsterWeld.Name = "HolsterWeld"
		holsterWeld.Parent = holsterModel
		holsterModel.Parent = player.Character
		holsterModel.Middle.Name = "Grip"
		holsterModel.Grip.Transparency = 1
	end

	if
		tool:FindFirstChild("Chambered")
		and holsterModel
		and holsterModel:FindFirstChild(wepStats.projectile)
		and not tool.Chambered.Value
	then
		local projectile = holsterModel:FindFirstChild(wepStats.projectile)
		projectile:Destroy()
	end
end

local function CheckHolster(player, tool)
	local wepStats = require(tool.SPH_Weapon.WeaponStats)
	if wepStats.holster then
		local holsterPart = player.Character:FindFirstChild(wepStats.holsterPart)
		if
			player.Character
			and not player.Character:FindFirstChild("Holster_" .. tool.Name)
			and not player.Character:FindFirstChild(tool.Name)
			and holsterPart
		then
			HolsterWeapon(player, holsterPart, tool, wepStats.holsterPosition)
		end
	end
end

local function RemoveHolster(player, toolName)
	if player.Character then
		local holsterModel = player.Character:FindFirstChild("Holster_" .. toolName)
		if holsterModel and not player.Backpack:FindFirstChild(toolName) then
			holsterModel:Destroy()
		end
	end
end

local function MakeCharacterRig(char: Model)
	local head = char:WaitForChild("Head", 20)
	local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")

	local rig = viewMod.RigModel(nil, true, head)
	rig.Parent = char

	local lArmWeld = weldMod.BlankWeld(rig["Left Arm"], char["Left Arm"])
	lArmWeld.Parent = rig
	lArmWeld.Name = "law"
	rig["Left Arm"].Transparency = 1

	local rArmWeld = weldMod.BlankWeld(rig["Right Arm"], char["Right Arm"])
	rArmWeld.Parent = rig
	rArmWeld.Name = "raw"
	rig["Right Arm"].Transparency = 1

	local animController = Instance.new("AnimationController", rig)
	local animator = Instance.new("Animator", animController)

	return rig
end

local function ToggleRig(character: Model, toggle: boolean)
	if character.Humanoid.RigType == Enum.HumanoidRigType.R6 then
		local torso = character.Torso
		local rig = character.WeaponRig
		torso["Left Shoulder"].Enabled = not toggle
		torso["Right Shoulder"].Enabled = not toggle
		rig.law.Enabled = toggle
		rig.raw.Enaabled = toggle
	end
end

local function SetupGun(tool: Tool, wepStats)
	-- First time setup
	tool.CanBeDropped = false
	if not tool:FindFirstChild("Ammo") then
		local ammoFolder = Instance.new("Folder", tool)
		ammoFolder.Name = "Ammo"

		local magAmmo = Instance.new("DoubleConstrainedValue", ammoFolder)
		magAmmo.Name = "MagAmmo"
		magAmmo.MaxValue = wepStats.magazineCapacity
		magAmmo.Value = wepStats.magazineAmmo or magAmmo.MaxValue

		local arcadeAmmoPool = Instance.new("DoubleConstrainedValue", ammoFolder)
		arcadeAmmoPool.Name = "ArcadeAmmoPool"
		arcadeAmmoPool.MaxValue = wepStats.maxAmmoPool
		arcadeAmmoPool.Value = wepStats.startAmmoPool

		if not wepStats.openBolt then
			local chambered = Instance.new("BoolValue", tool)
			chambered.Value = wepStats.startChambered
			chambered.Name = "Chambered"

			if chambered.Value then
				if magAmmo.Value > 0 then
					magAmmo.Value -= 1
				else
					chambered.Value = false
				end
			end
		end

		local boltReady = Instance.new("BoolValue", tool)
		boltReady.Value = true
		boltReady.Name = "BoltReady"

		local fireMode = Instance.new("IntValue", tool)
		fireMode.Value = wepStats.fireMode
		fireMode.Name = "FireMode"
	end
end

local function EquipGun(rig: Model, tool: Tool)
	if tool.Parent == rig.Parent and assets.WeaponModels:FindFirstChild(tool.Name) then
		local wepStats = require(tool.SPH_Weapon.WeaponStats)
		local gun = assets.WeaponModels[tool.Name]:Clone()

		if not wepStats.disableAutoRigging then -- Auto rigging
			weldMod.WeldModel(gun, gun.Grip, false)

			for _, partName in ipairs(wepStats.rigParts) do
				if gun:FindFirstChild(partName) then
					gun.Grip["Grip_" .. partName]:Destroy()
					local newMotor = weldMod.M6D(gun.Grip, gun[partName])
					newMotor.Name = partName
					newMotor.Parent = gun.Grip
				end
			end

			-- Disable collisions on gun model including descendants
			for _, desc: BasePart in gun:GetDescendants() do
				if desc:IsA("BasePart") then
					desc.CanCollide = false
				end
			end
		end

		-- Check for projectile visibility
		local projectile = gun:FindFirstChild(wepStats.projectile)
		if (wepStats.openBolt or not tool.Chambered.Value) and projectile and wepStats.projectile ~= "Bullet" then
			projectile:SetAttribute("OriginalTransparency", projectile.Transparency)
			projectile.Transparency = 1
			for _, child in ipairs(projectile:GetDescendants()) do
				if child:IsA("BasePart") then
					child.Transparency = 1
				end
			end
		end

		-- Remove sight
		for _, part in ipairs(gun:GetChildren()) do
			if part.Name == "SightReticle" and part:FindFirstChild("SurfaceGui") then
				part.SurfaceGui.Enabled = false
			end
		end

		gun.Parent = rig.Weapon
		if rig.AnimBase:FindFirstChild("GunMotor") then
			rig.AnimBase:FindFirstChild("GunMotor"):Destroy()
		end
		local gunMotor = weldMod.BlankM6D(rig.AnimBase, gun.Grip)
		gunMotor.Name = "GunMotor"
		rig.law.Enabled = true
		rig.raw.Enabled = true

		rig.BaseWeld.C0 = wepStats.serverOffset

		SetupGun(tool, wepStats)

		return gun
	end
end

local function IsGunLoaded(tool)
	local wepStats = require(tool.SPH_Weapon.WeaponStats)
	local gunAmmo = tool.Ammo
	local magAmmo = gunAmmo.MagAmmo
	return not wepStats.openBolt and tool.Chambered.Value or wepStats.openBolt and gunAmmo.MagAmmo.Value > 0
end

local function PlayerFire(player: Player, firePoint: CFrame)
	local tool = player.Character:FindFirstChildWhichIsA("Tool")
	if not tool or not tool:IsA("Tool") then
		warn(warnPrefix .. "PlayerFire Canceled: No tool was found. Player: " .. player.Name)
		return
	end
	local wepStats = require(tool.SPH_Weapon.WeaponStats)
	local gunAmmo = tool.Ammo
	local magAmmo = gunAmmo.MagAmmo
	if wepStats.fireMode == 4 then
		if not wepStats.openBolt then
			tool.Chambered.Value = false
		end
		tool.BoltReady.Value = false
	elseif not IsGunLoaded(tool) then
		if tool.BoltReady.Value then
			return
		elseif wepStats.emptyCloseBolt then
			tool.BoltReady.Value = true
			return
		end
	else
		if not wepStats.openBolt then
			tool.Chambered.Value = false
		end
		tool.BoltReady.Value = not wepStats.emptyLockBolt
		if magAmmo.Value > 0 then
			magAmmo.Value -= 1
			if not wepStats.openBolt then
				tool.Chambered.Value = true
			end
			tool.BoltReady.Value = true
		end
	end

	local point = player.Character.HumanoidRootPart.Position
	local dist = config.fireEffectDistance
	repFire:FireAllInRangeExcept(player, point, dist, player, firePoint)
end

local function TeamKillCheck(player1: Player, player2: Player)
	-- Teamkill stuff
	if not config.teamKill and not player1.Neutral and not player2.Neutral then
		if player1.Team == player2.Team then
			return false
		end
	end
	return true
end

local function CheckTool(player, tool)
	if tool:FindFirstChild("SPH_Weapon") and assets.WeaponModels:FindFirstChild(tool.Name) then
		CheckHolster(player, tool)
		local wepStats = require(tool.SPH_Weapon.WeaponStats)
		SetupGun(tool, wepStats)
	end
end

local function MakePickUpAble(tool, model, mainPart)
	tool.Parent = model
	model.Name = tool.Name

	local proxPrompt = Instance.new("ProximityPrompt")
	proxPrompt.MaxActivationDistance = config.pickupDistance
	proxPrompt.Style = Enum.ProximityPromptStyle.Custom
	proxPrompt.RequiresLineOfSight = false
	proxPrompt.KeyboardKeyCode = config.pickupKey[1]
	proxPrompt.HoldDuration = 0
	proxPrompt.Parent = mainPart

	local promptListener
	promptListener = proxPrompt.Triggered:Connect(function(player)
		if player.Character.Humanoid.Health <= 0 then
			return
		else
			promptListener:Disconnect()
		end

		tool.Parent = player.Backpack
		model:Destroy()

		local newSound = assets.Sounds.Misc.WeaponPickup:Clone()
		newSound.Parent = player.Character.HumanoidRootPart
		newSound:Play()
		newSound.PlayOnRemove = true
		newSound:Destroy()
	end)

	local highlight = Instance.new("Highlight")
	highlight.Name = "PickupHighlight"
	highlight.FillTransparency = 0.7
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.Parent = model
	highlight.Enabled = false
end

local function SpawnGun(tool, gunPosition, dropPlayer)
	local wepStats = require(tool.SPH_Weapon.WeaponStats)
	local dropModel = assets.WeaponModels:FindFirstChild(tool.Name)
	if not dropModel then
		return
	end
	dropModel = dropModel:Clone()
	dropModel.Grip.Anchored = false
	dropModel.Grip.CanTouch = true

	task.delay(config.dropGunAnchorTime, function()
		for _, desc in dropModel:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.Anchored = true
				desc.CanCollide = false
			end
		end
	end)

	dropModel.PrimaryPart = dropModel.Grip
	dropModel.Grip.Size = dropModel:GetExtentsSize()

	if #dropModel:GetChildren() < 2 then
		dropModel.Grip.CanCollide = true
	else
		dropModel.Grip.CanCollide = false
	end

	for _, part in ipairs(dropModel:GetDescendants()) do
		if part:IsA("BasePart") then
			if string.find(part.Name, "AimPart") then
				part:Destroy()
			elseif part.Name ~= "Grip" then
				local newWeld = weldMod.Weld(dropModel.Grip, part)
				newWeld.Parent = dropModel.Grip
				part.Anchored = false
				part.CanCollide = true
				part.CanTouch = false
				part.CollisionGroup = "Guns"
			end
		end
	end

	if not tool then
		local tool = assets.ToolStorage:FindFirstChild(tool.Name)
		if tool then
			tool = tool:Clone()
		else
			warn("No tool could be found for this pickup. Did you forget to put one in ToolStorage?")
			return
		end
	end

	MakePickUpAble(tool, dropModel, dropModel.Grip)

	-- Check for projectile visibility
	local projectile = dropModel:FindFirstChild(wepStats.projectile)
	if (wepStats.openBolt or not tool.Chambered.Value) and projectile and wepStats.projectile ~= "Bullet" then
		projectile.Transparency = 1
		for _, child in ipairs(projectile:GetDescendants()) do
			if child:IsA("BasePart") then
				child.Transparency = 1
			end
		end
	end

	dropModel.Parent = drops

	dropModel.Grip.Touched:Connect(function()
		if dropModel.Grip.AssemblyLinearVelocity.Magnitude > 7 then
			local DropSounds = assets.Sounds.GunDrop
			local NewSound = DropSounds["GunDrop" .. math.random(#DropSounds:GetChildren())]:Clone()
			NewSound.Parent = dropModel.Grip
			NewSound.PlaybackSpeed = math.random(30, 50) / 40
			NewSound:Play()
			NewSound.PlayOnRemove = true
			NewSound:Destroy()
		end
	end)

	if dropPlayer then
		dropModel.Grip:SetNetworkOwner(dropPlayer)
	end

	dropModel:SetPrimaryPartCFrame(gunPosition)

	local position = #dropTable + 1
	table.insert(dropTable, position, dropModel)

	if #dropTable > config.maxDroppedGuns then
		local objectToDestroy = dropTable[1]
		table.remove(dropTable, 1)
		objectToDestroy:Destroy()
	end

	task.delay(config.dropDespawnTime, function()
		table.remove(dropTable, position)
		dropModel:Destroy()
	end)

	return dropModel
end

players.PlayerAdded:Connect(function(newPlayer: Player)
	print(warnPrefix .. newPlayer.Name .. " joined the server")

	if config.serverBanList and table.find(naughtyList, newPlayer.UserId) then
		newPlayer:Kick("Disconnected")
		warn(warnPrefix .. newPlayer.Name .. " attempted to join a server they've been banned from")
		return
	elseif config.strikes then
		newPlayer:SetAttribute("Strikes", 0)
		newPlayer:GetAttributeChangedSignal("Strikes"):Connect(function()
			if newPlayer:GetAttribute("Strikes") >= config.maxStrike then
				table.insert(naughtyList, newPlayer.UserId)
				newPlayer:Kick("Disconnected")
				warn(
					warnPrefix
						.. newPlayer.Name
						.. " was kicked for reaching "
						.. newPlayer:GetAttribute("Strikes")
						.. " strikes. Last strike reason: '"
						.. newPlayer:GetAttribute("LastStrikeReason")
						.. "'"
				)
			end
		end)
	end

	sysMessage:FireAll("[SYSTEM] User '" .. newPlayer.Name .. "' joined the server.", Color3.new(0, 1, 0.615686))

	local deaths
	if config.leaderboard then
		local leaderstats = newPlayer:FindFirstChild("leaderstats")
		if not leaderstats then
			leaderstats = Instance.new("Folder", newPlayer)
			leaderstats.Name = "leaderstats"
		end
		local kills = Instance.new("IntValue", leaderstats)
		kills.Name = "K"
		deaths = Instance.new("IntValue", leaderstats)
		deaths.Name = "D"
	end

	newPlayer.CharacterAdded:Connect(function(newChar: Model)
		print(warnPrefix .. newPlayer.Name .. " spawned.")
		local humanoid = newChar:WaitForChild("Humanoid", 20)
		local animator = humanoid:WaitForChild("Animator", 20)
		-- Set up all new characters with an animation rig
		local newRig = MakeCharacterRig(newChar)
		humanoid.BreakJointsOnDeath = not config.ragdolls
		--humanoid.RequiresNeck = config.ragdolls
		humanoid.Died:Connect(function()
			if not newChar:FindFirstChild("HumanoidRootPart") then
				return
			end
			newChar.Humanoid:UnequipTools()

			-- This line of code attempts to find a default roblox damage tag
			-- They are very inconsistent :(
			local robloxDamageTag = newChar.Humanoid:FindFirstChildWhichIsA("ObjectValue")
			--if robloxDamageTag then print("wow!") end

			-- Death message
			local killer = newChar:FindFirstChild("Killer")
			if not killer then
				-- Died of unknown cause (probably reset or died via admin command)
				local newMsg = systemMessages.GetMessage("Death")
				sysMessage:FireAll(newPlayer.Name .. " " .. newMsg, Color3.new(0.7, 0.7, 0.7))
			elseif killer:IsA("ObjectValue") and killer.Value:IsA("Player") then
				-- Was killed by another player using spearhead
				local newMsg = systemMessages.GetMessage("Killed")
				sysMessage:FireAll(newPlayer.Name .. " " .. newMsg .. " " .. killer.Value.Name, Color3.new(1, 0, 0))
			elseif
				robloxDamageTag
				and robloxDamageTag.Value
				and robloxDamageTag.Value:IsA("Player")
				and config.rblxDamageTags
			then
				-- A roblox damage tag was found!
				killer = robloxDamageTag
				local newMsg = systemMessages.GetMessage("Killed")
				sysMessage:FireAll(killer.Value.Name .. " " .. newMsg .. " " .. newPlayer.Name, Color3.new(1, 0, 0))
			elseif killer:IsA("StringValue") then
				-- Death was not due to a player
				if killer.Value == "Falling" then
					-- Died of fall damage
					local newMsg = systemMessages.GetMessage("Falling")
					sysMessage:FireAll(newPlayer.Name .. " " .. newMsg, Color3.new(1, 0, 0))
				end
			end

			-- Destroy animation rig
			newRig:Destroy()

			-- Increase death stat
			if config.leaderboard then
				deaths.Value += 1
			end

			-- Ragdoll
			local hrp, newBody
			if config.ragdolls and newChar:FindFirstChild("HumanoidRootPart") then
				newBody = ragdoll.MakeCorpse(newChar)
				newBody.Parent = bodies
				hrp = newBody.HumanoidRootPart
				debris:AddItem(newBody, config.bodyDespawn)
				if #bodies:GetChildren() > config.bodyLimit then
					bodies:GetChildren()[1]:Destroy()
				end

				local torso
				if humanoid.RigType == Enum.HumanoidRigType.R6 then
					torso = newBody.Torso
				else
					torso = newBody.UpperTorso
				end

				local deathForce = Instance.new("VectorForce", torso.NeckAttachment)
				deathForce.Attachment0 = deathForce.Parent
				deathForce.Force = Vector3.new(0, 0, -600)
				debris:AddItem(deathForce, 0.2)

				delay(config.bodyAnchorTime, function()
					for _, desc in newBody:GetDescendants() do
						if desc:IsA("BasePart") then
							desc.Anchored = true
							desc.CanCollide = false
						elseif desc:IsA("Constraint") then
							desc.Enabled = false
						end
					end
				end)
			else
				hrp = newChar.HumanoidRootPart
			end

			-- Gun Drops
			if config.dropOnDeath then
				local equippedTool = newChar:FindFirstChildWhichIsA("Tool")
				if equippedTool and equippedTool:FindFirstChild("SPH_Weapon") then
					SpawnGun(equippedTool, newChar.HumanoidRootPart.CFrame * dropCFrame, newPlayer)
				end

				for _, tool in ipairs(newPlayer.Backpack:GetChildren()) do
					if tool:FindFirstChild("SPH_Weapon") then
						local holsterModel = newBody and newBody:FindFirstChild("Holster_" .. tool.Name)
						if holsterModel and newBody then
							MakePickUpAble(tool, holsterModel, holsterModel.Grip)
						else
							SpawnGun(tool, newBody.HumanoidRootPart.CFrame * dropCFrame, newPlayer)
							task.wait()
						end
					end
				end
			end

			-- Death sound
			local deathSounds = assets.Sounds.Death:GetChildren()
			local newSound = deathSounds[math.random(#deathSounds)]:Clone()
			newSound.Parent = hrp
			newSound:Play()
			debris:AddItem(newSound, newSound.TimeLength)
		end)

		newPlayer.Backpack.ChildAdded:Connect(function(child)
			if child:FindFirstChild("SPH_Weapon") then
				CheckTool(newPlayer, child)
			end
		end)

		newPlayer.Backpack.ChildRemoved:Connect(function(child)
			if child:FindFirstChild("SPH_Weapon") then
				RemoveHolster(newPlayer, child.Name)
			end
		end)

		for _, tool in ipairs(newPlayer.Backpack:GetChildren()) do
			if tool:FindFirstChild("SPH_Weapon") then
				CheckTool(newPlayer, tool)
			end
		end

		for _, part in ipairs(newChar:GetChildren()) do
			if part:IsA("BasePart") then
				if part.Name == "HumanoidRootPart" then
					part.CollisionGroup = "RootParts"
				else
					part.CollisionGroup = "Players"
				end
			end
		end

		local humanoidRootPart = newChar.HumanoidRootPart

		local soundOrigin = Instance.new("Attachment", humanoidRootPart)
		soundOrigin.Name = "FootstepSoundOrigin"
		soundOrigin.Position = Vector3.new(0, -3, 0)

		local leftFoot = Instance.new("Sound", soundOrigin)
		leftFoot.Name = "LeftFoot"
		leftFoot.Volume = 1
		leftFoot.RollOffMode = Enum.RollOffMode.InverseTapered
		leftFoot.RollOffMaxDistance = 100

		local rightFoot = Instance.new("Sound", soundOrigin)
		rightFoot.Name = "RightFoot"
		rightFoot.Volume = 1
		rightFoot.RollOffMode = Enum.RollOffMode.InverseTapered
		rightFoot.RollOffMaxDistance = 100

		task.wait() -- If the script doesn't yield for a moment, the guis get added too early then deleted for some reason?
		local newGui = mainui:Clone()
		newGui.Parent = newPlayer.PlayerGui

		if config.deathScreen then
			assets.HUD.DeathScreen:Clone().Parent = newPlayer.PlayerGui
		end
	end)
end)

players.PlayerRemoving:Connect(function(player)
	print(warnPrefix .. player.Name .. " left the server")
	sysMessage:FireAll("[SYSTEM] User '" .. player.Name .. "' left the server.", Color3.new(0, 1, 0.615686))

	-- Drop guns when leaving
	local character = player.Character
	if config.dropOnLeave and character then
		local equippedTool = character:FindFirstChildWhichIsA("Tool")
		if equippedTool and equippedTool:FindFirstChild("SPH_Weapon") then
			SpawnGun(equippedTool, character.HumanoidRootPart.CFrame * dropCFrame, player)
		end

		for _, tool in ipairs(player.Backpack:GetChildren()) do
			if tool:FindFirstChild("SPH_Weapon") then
				SpawnGun(tool, character.HumanoidRootPart.CFrame * dropCFrame, player)
				task.wait()
			end
		end
	end
end)

-- Update head movement for other players
bodyAnimRequest:Connect(function(player: Player, angle)
	if
		player.Character
		and (player.Character:FindFirstChild("Torso") or player.Character:FindFirstChild("UpperTorso"))
		and player.Character.Humanoid.Health > 0
	then
		bodyAnimCommand:FireAllInRangeExcept(
			player,
			player.Character.HumanoidRootPart.Position,
			config.animDistance,
			player.Character,
			angle
		)
	end
end)

-- Player equipped or unequipped a weapon
switchWeapon:Connect(function(player: Player, tool: Tool)
	if player.Character and player.Character:FindFirstChild("WeaponRig") and player.Character.Humanoid.Health > 0 then
		local rig = player.Character.WeaponRig
		local curWeapon = player.Character.WeaponRig.Weapon:FindFirstChildWhichIsA("Model")
		local torso
		if player.Character.Humanoid.RigType == Enum.HumanoidRigType.R6 then
			torso = player.Character.Torso
		else
			torso = player.Character.UpperTorso
		end
		if curWeapon then
			torso["Left Shoulder"].Enabled = true
			torso["Right Shoulder"].Enabled = true
			rig.law.Enabled = false
			rig.raw.Enabled = false
			curWeapon:Destroy()
		end

		if player.Character.Humanoid.Health > 0 and tool and typeof(tool) == "Instance" then
			torso["Left Shoulder"].Enabled = false
			torso["Right Shoulder"].Enabled = false
			EquipGun(player.Character.WeaponRig, tool)
		end
	end
end)

repReload:Connect(function(player: Player)
	if config.listenForReloadSpam then
		if player:GetAttribute("LastReload") then
			if time() - player:GetAttribute("LastReload") <= 0.3 then
				return
			end
		end

		player:SetAttribute("LastReload", time())
	end

	local tool = player.Character:FindFirstChildWhichIsA("Tool")
	if not tool then
		return
	end

	local wepStats = require(tool.SPH_Weapon.WeaponStats)
	local magAmmo = tool.Ammo.MagAmmo
	local arcadeAmmoPool = tool.Ammo.ArcadeAmmoPool

	if not wepStats.operationType or type(wepStats.operationType) == "string" then
		wepStats.operationType = 1
	end

	if not wepStats.magType or type(wepStats.magType) == "string" then
		wepStats.magType = 1
	end

	if wepStats.infiniteAmmo then
		-- Gun has infinite ammo

		if wepStats.magType == 2 then
			-- Insert only
			magAmmo.Value += 1
		elseif wepStats.magType == 3 then
			-- Insert and clip
			local ammoNeeded = magAmmo.MaxValue - magAmmo.Value
			local clipSize = (wepStats.clipSize or wepStats.magazineCapacity)
			if ammoNeeded >= clipSize then
				magAmmo.Value += clipSize
			else
				magAmmo.Value += 1
			end
		else
			-- Magazine
			magAmmo.Value = magAmmo.MaxValue
		end
	elseif arcadeAmmoPool.Value > 0 then
		if wepStats.magType == 1 or wepStats.magType == 4 then
			-- Magazine fed

			-- Gun has ammo remaining in its pool
			local ammoNeeded = magAmmo.MaxValue - magAmmo.Value
			if arcadeAmmoPool.Value > ammoNeeded then
				-- There is enough ammo in the pool for a full magazine
				magAmmo.Value = magAmmo.MaxValue
				arcadeAmmoPool.Value -= ammoNeeded
			else
				-- There is not enough ammo in the pool for a full magazine
				magAmmo.Value += arcadeAmmoPool.Value
				arcadeAmmoPool.Value = 0
			end
		elseif wepStats.magType == 2 then
			-- Insert only

			if arcadeAmmoPool.Value > 0 then
				magAmmo.Value += 1
				arcadeAmmoPool.Value -= 1
			end
		elseif wepStats.magType == 3 then
			-- Insert and clips

			local ammoNeeded = magAmmo.MaxValue - magAmmo.Value
			local clipSize = (wepStats.clipSize or wepStats.magazineCapacity)

			if ammoNeeded >= clipSize and arcadeAmmoPool.Value >= ammoNeeded then
				magAmmo.Value += clipSize
				arcadeAmmoPool.Value -= clipSize
			else
				magAmmo.Value += 1
				arcadeAmmoPool.Value -= 1
			end
		end
	end

	if wepStats.operationType == 4 and not tool.Chambered.Value then
		tool.Chambered.Value = true
		magAmmo.Value -= 1
	end

	local gunModel = player.Character.WeaponRig.Weapon:FindFirstChildWhichIsA("Model")
	if wepStats.projectile and gunModel:FindFirstChild(wepStats.projectile) then
		local projectile = gunModel:FindFirstChild(wepStats.projectile)
		projectile.Transparency = projectile:GetAttribute("OriginalTransparency") or 0
		for _, child in ipairs(projectile:GetDescendants()) do
			if child:IsA("BasePart") then
				child.Transparency = 0
			end
		end
	end
end)

playSound:Connect(function(player: Player, soundName: string)
	local weapon = player.Character.WeaponRig.Weapon:FindFirstChildWhichIsA("Model")
	if not weapon then
		warn(warnPrefix .. "No weapon found when trying to play: '" .. soundName .. "'")
		return
	end
	local soundToPlay = weapon.Grip:FindFirstChild(soundName)
	if soundToPlay then
		repSound:FireToAllExcept(player, player, soundToPlay)
	end
end)

bulletHit:Connect(function(player: Player, tool: Tool, raycastResult: RaycastResult, bulletCFrame: CFrame)
	if config.ammoCountCheck then
		if player:GetAttribute("LastFiredGun") then
			local lastFiredGun = player:GetAttribute("LastFiredGun")
			local lastFiredMagCount = player:GetAttribute("LastFiredMagCount")
			if player.Character:FindFirstChild(lastFiredGun) and lastFiredMagCount == tool.Ammo.MagAmmo.Value then
				return
			end
		end

		player:SetAttribute("LastFiredGun", tool.Name)
		player:SetAttribute("LastFiredMagCount", tool.Ammo.MagAmmo.Value)
	end

	if player and CheckNaughtyList(player.UserId) then
		return
	end
	if not tool then
		return
	elseif tool and typeof(tool) ~= "Instance" then
		warn(warnPrefix .. player.Name .. " attempted to call bulletHit without a tool.")
		return
	elseif config.requireEquippedGun and tool.Parent ~= player.Character then -- Don't deal damage when not equipped
		if config.strikes then
			player:SetAttribute("Strikes", player:GetAttribute("Strikes") + 1)
			player:SetAttribute("LastStrikeReason", "Attempting to deal damage with no tool equipped")
		end
		return
	elseif tool.Parent ~= player.Character and tool.Parent ~= player.Backpack then -- Cannot use other player's tools
		return
	end
	local wepStats
	if typeof(tool) == "table" then
		wepStats = require(tool.model.Parent.TurretModule).guns[tool.index]
	elseif tool:IsA("Tool") then
		wepStats = require(tool.SPH_Weapon.WeaponStats)
	end

	-- Check for explosions
	if wepStats.explosiveAmmo then
		-- Explosion
		explosionMod(raycastResult.Position, wepStats.explosionRadius, wepStats.explosionEffect, player)

		if config.listenForExplosionSpam then
			local lastExplosion = player:GetAttribute("LastExplosion")
			if lastExplosion and time() - lastExplosion <= 0.3 then
				table.insert(naughtyList, player.UserId)
				player:Kick("Disconnected")
				warn(warnPrefix .. player.Name .. " was kicked for trying to create multiple explosions at once!")
				return
			end
			player:SetAttribute("LastExplosion", time())
		end
	else
		-- Replicate hit effect to other clients
		local position = raycastResult.Position
		repHit:FireAllInRangeExcept(player, position, config.maxHitDistance, tool, raycastResult)
	end

	-- Server-side hit effects
	local hitPart: BasePart = raycastResult.Instance
	if not hitPart or not hitPart.Parent then
		return
	end
	local humanoid: Humanoid = hitPart.Parent:FindFirstChildWhichIsA("Humanoid")
	local otherPlayer
	if humanoid then
		otherPlayer = players:GetPlayerFromCharacter(humanoid.Parent)
	end
	local damage = wepStats.damage[hitPart.Name] or wepStats.damage.Other

	-- Damage
	if
		humanoid
		and humanoid.Health > 0
		and ((otherPlayer and TeamKillCheck(player, otherPlayer)) or not otherPlayer)
	then
		if config.serverSideHitCheck then
			-- Raycast check
			local bulletRay: RaycastResult =
				hitscan.FireHitscanBullet( -- Sends a raycast from the player's head to where they claim they hit
					player.Character.Head.Position,
					(raycastResult.Position - player.Character.Head.Position).Unit,
					config.maxBulletDistance,
					MergeTables(
						ignoreParts,
						{ player.Character, workspace.SPH_Workspace.Cache, workspace.SPH_Workspace.Shells }
					)
				)

			if not bulletRay or bulletRay.Instance ~= raycastResult.Instance then
				return -- Bullet hit nothing
			end
		end

		-- Hit a humanoid, deal damage!
		if humanoid.Health > 0 and humanoid.Health - damage <= 0 then
			if config.leaderboard then
				player.leaderstats.K.Value += 1
			end
			local killer = Instance.new("ObjectValue", humanoid.Parent)
			killer.Name = "Killer"
			killer.Value = player

			if config.printKillLogs and player and otherPlayer then
				print(warnPrefix .. " " .. player.Name .. " killed " .. otherPlayer.Name)
			end

			if config.listenForKillAll then
				if player:GetAttribute("LastKillTime") then
					local lastTime = player:GetAttribute("LastKillTime")
					if time() - lastTime <= 0.1 then
						player:SetAttribute("MultiKill", (player:GetAttribute("MultiKill") or 0) + 1)
						if player:GetAttribute("MultiKill") > config.multiKillThreshold then
							table.insert(naughtyList, player.UserId)
							player:Kick("Disconnected")
							warn(warnPrefix .. player.Name .. " was kicked for killing too quickly!")
							return
						end
					else
						player:SetAttribute("MultiKill", 0)
					end
					if
						config.multiKillDistanceCheck
						and time() - lastTime < 3
						and (humanoid.Parent.WorldPivot.Position - player:GetAttribute("LastKillPosition")).Magnitude
							> 100
					then
						warn(warnPrefix .. player.Name .. " attempted to kill two players >100 from each other!")

						if config.strikes then
							player:SetAttribute("Strikes", player:GetAttribute("Strikes") + 1)
							player:SetAttribute(
								"LastStrikeReason",
								"Attempting to kill multiple players >100 studs apart"
							)
						end

						return
					end
				end

				player:SetAttribute("LastKillTime", time())
				player:SetAttribute("LastKillPosition", humanoid.Parent.WorldPivot.Position)
			end
		end

		if config.killAngleCheck then
			local headCFrame = player.Character.HumanoidRootPart.CFrame
			local otherHumanoidPosition = humanoid.Parent.WorldPivot.Position
			local positionDifference = (headCFrame.Position - otherHumanoidPosition).Unit
			local angleToTarget = math.pow((headCFrame.LookVector - positionDifference).Magnitude / 2, 2)
			if angleToTarget < 0.5 then
				return
			end -- Can't damage players that you aren't facing
		end

		-- This should work with most roblox leaderboards
		local creator = Instance.new("ObjectValue")
		creator.Name = "creator"
		creator.Value = player
		creator.Parent = humanoid
		debris:AddItem(creator, 0.5)

		humanoid:TakeDamage(damage)
	elseif
		(hitPart.Name == "Glass" or collectionService:HasTag(hitPart, "BreakableGlass"))
		and config.glassShatter
		and not hitPart:GetAttribute("Shattered")
	then -- Glass shatter
		hitPart:SetAttribute("Shattered", true)
		local hitPosition = raycastResult.Position

		local tempPart = hitPart:Clone()
		tempPart.Name = "TempGlass"
		tempPart.Parent = workspace

		local prevTransparency = hitPart.Transparency
		local prevCanCollide = hitPart.CanCollide
		local prevCanQuery = hitPart.CanQuery
		local prevCanTouch = hitPart.CanTouch

		hitPart.Transparency = 1
		hitPart.CanCollide = false
		hitPart.CanQuery = false
		hitPart.CanTouch = false

		delay(config.glassRespawnTime, function()
			if hitPart and hitPart.Parent then
				hitPart.Transparency = prevTransparency
				hitPart.CanCollide = prevCanCollide
				hitPart.CanQuery = prevCanQuery
				hitPart.CanTouch = prevCanTouch
				hitPart:SetAttribute("Shattered", false)
			end
		end)

		if hitPart:IsA("Part") and hitPart.Shape == Enum.PartType.Block or hitPart:IsA("WedgePart") then
			fractureGlass(tempPart, hitPosition, bulletCFrame.LookVector * 10)
		else
			tempPart:Destroy()
		end

		local soundAtt = Instance.new("Attachment", workspace.Terrain)
		soundAtt.WorldPosition = hitPosition
		local shatterSound =
			assets.Sounds.GlassBreak:GetChildren()[math.random(#assets.Sounds.GlassBreak:GetChildren())]:Clone()
		shatterSound.Parent = soundAtt
		shatterSound:Play()
		debris:AddItem(soundAtt, shatterSound.TimeLength)
	elseif not hitPart.Anchored and config.useBulletForce and ((humanoid and humanoid.Health <= 0) or not humanoid) then
		-- Push part with force from bullet
		local tempAtt = Instance.new("Attachment", hitPart)
		tempAtt.WorldCFrame = CFrame.new(raycastResult.Position) * (bulletCFrame - bulletCFrame.Position)
		local force = Instance.new("VectorForce", tempAtt)
		force.Attachment0 = tempAtt
		force.Force = Vector3.new(0, 0, -wepStats.bulletForce)
		debris:AddItem(tempAtt, 0.1)
		if not otherPlayer or humanoid.Health <= 0 then
			pcall(function()
				hitPart:SetNetworkOwner(player)
			end)
		end
	end

	-- Object destruction
	local hitObject: Instance
	if hitPart.Parent:HasTag("SPH_Destructible") then
		hitObject = hitPart.Parent
	elseif hitPart:HasTag("SPH_Destructible") then
		hitObject = hitPart
	end

	if hitObject and not hitObject:GetAttribute("Destroyed") then
		local objectHealth = hitObject:GetAttribute("HP")
		hitObject:SetAttribute("HP", objectHealth - damage)
		objectHealth -= damage

		if objectHealth <= 0 then
			objectDestruction.DestroyObject(hitObject)
		end
	end
end)

repChamber:Connect(function(player: Player)
	local tool = player.Character:FindFirstChildWhichIsA("Tool")
	if tool and tool.Parent == player.Character then
		tool.BoltReady.Value = true
		if tool:FindFirstChild("Chambered") then
			tool.Chambered.Value = false
		end
		if tool.Ammo.MagAmmo.Value > 0 and tool:FindFirstChild("Chambered") then
			tool.Ammo.MagAmmo.Value -= 1
			tool.Chambered.Value = true
		end
	end
end)

repBoltOpen:Connect(function(player: Player)
	local tool = player.Character:FindFirstChildWhichIsA("Tool")
	if tool and tool.Parent == player.Character then
		tool.BoltReady.Value = false
		if tool:FindFirstChild("Chambered") then
			tool.Chambered.Value = false
		end
	end
end)

fallDamage:Connect(function(player, damage)
	damage = math.abs(damage)
	local humanoid = player.Character:FindFirstChild("Humanoid")
	if humanoid then
		if humanoid.Health <= damage then
			local killer = Instance.new("StringValue", player.Character)
			killer.Name = "Killer"
			killer.Value = "Falling"
		end
		player.Character.Humanoid:TakeDamage(damage)
		local fallSounds = assets.Sounds.FallDamage
		local newSound
		if damage <= 10 then
			newSound = fallSounds.Fall1
		elseif damage <= 30 then
			newSound = fallSounds.Fall2
		elseif damage <= 60 then
			newSound = fallSounds.Fall3
		else
			newSound = fallSounds.Fall4
		end
		newSound = newSound:Clone()
		newSound.PlaybackSpeed += math.random(-10, 10) / 100
		newSound.Parent = player.Character.PrimaryPart
		newSound:Play()
		debris:AddItem(newSound, newSound.TimeLength)
	end
end)

moveBolt:Connect(function(player, direction, magAmmo)
	if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
		local playerPosition = player.Character.HumanoidRootPart.Position
		repBolt:FireAllInRangeExcept(player, playerPosition, config.fireEffectDistance, player, direction, magAmmo)
	end
end)

switchFireMode:Connect(function(player, newFireMode)
	local tool = player.Character:FindFirstChildWhichIsA("Tool")
	if tool and tool:FindFirstChild("SPH_Weapon") then
		tool.FireMode.Value = newFireMode
	end
end)

proxPromptService.PromptTriggered:Connect(function(prompt, player)
	if prompt.Name == "AmmoGiver" and prompt:FindFirstChild("SPH_PromptConfig") then
		local ammoTaken = false
		local promptConfig = prompt.SPH_PromptConfig
		local ammoPool = promptConfig.AmmoPool
		if ammoPool.Value < 1 and not promptConfig.InfAmmo.Value then
			return
		end
		local ammoType = promptConfig.AmmoType.Value

		local tools = player.Backpack:GetChildren()
		local equippedTool = player.Character:FindFirstChildWhichIsA("Tool")
		if equippedTool then
			table.insert(tools, equippedTool)
		end

		for _, tool in ipairs(tools) do
			if tool:FindFirstChild("SPH_Weapon") then
				local wepStats = require(tool.SPH_Weapon.WeaponStats)
				local arcadeAmmoPool = tool.Ammo.ArcadeAmmoPool

				if wepStats.infiniteAmmo then
					-- This gun has infinite ammo
					continue
				elseif
					arcadeAmmoPool.Value < arcadeAmmoPool.MaxValue
					and (wepStats.ammoType == ammoType or ammoType == "Universal")
				then
					-- This gun could use some ammo
					ammoTaken = true
					local ammoNeeded = arcadeAmmoPool.MaxValue - arcadeAmmoPool.Value
					if ammoPool.Value > ammoNeeded then
						-- There is enough ammo in the pool for a full refill
						arcadeAmmoPool.Value = arcadeAmmoPool.MaxValue
						ammoPool.Value -= ammoNeeded
					else
						-- There is not enough ammo in the pool for a full refill
						arcadeAmmoPool.Value += ammoPool.Value
						ammoPool.Value = 0
					end

					if ammoPool.Value <= 0 and config.despawnEmptyAmmoBoxes then
						prompt.Enabled = false
						task.delay(config.ammoBoxDespawnTime, function()
							if ammoPool.Value <= 0 then
								prompt.Parent.Parent:Destroy()
							end
						end)
					end
				elseif arcadeAmmoPool.Value <= 0 then
					break
				end
			end
		end

		if ammoTaken and prompt.Parent:FindFirstChild("Ammo") then
			prompt.Parent.Ammo:Play()
		end
	elseif prompt.Name == "GunGiver" and prompt:FindFirstChild("SPH_PromptConfig") then
		local config = prompt.SPH_PromptConfig
		local gunName = prompt:GetAttribute("ToolToGive") or prompt:FindFirstChildWhichIsA("Tool").Name
		local gunPool = config.GunPool

		-- If dupes are not allowed, don't allow the player to pick up this gun
		if
			not config.AllowDupes.Value
			and (player.Character:FindFirstChild(gunName) or player.Backpack:FindFirstChild(gunName))
		then
			return
		end

		if gunPool.Value > 0 or config.InfGuns.Value then
			local newGun = prompt:FindFirstChildWhichIsA("Tool")
				or game.ReplicatedStorage.SPH_Assets.ToolStorage:FindFirstChild(gunName)
			if not newGun then
				return
			else
				newGun = newGun:Clone()
			end
			newGun.Parent = player.Backpack
			gunPool.Value -= 1

			if gunPool.Value < 1 then
				prompt.Enabled = false
				local listener
				listener = gunPool.Changed:Connect(function()
					if gunPool.Value > 0 then
						listener:Disconnect()
						prompt.Enabled = true
					end
				end)
			end

			local gunModels = prompt.Parent.Parent:FindFirstChild("GunModels")
			if
				not config.InfGuns.Value
				and config.RemoveModels.Value
				and gunModels
				and #gunModels:GetChildren() > gunPool.Value
			then
				gunModels:GetChildren()[1]:Destroy()
			end

			if prompt.Parent:FindFirstChild("TakeGun") then
				prompt.Parent.TakeGun:Play()
			end
		end
	end
end)

playerFire:Connect(PlayerFire)

replicatedStorage.SPH_Assets.Events.PlayCharacterSound.OnServerEvent:Connect(function(player, soundType)
	local lastCharacterSound = player:GetAttribute("LastCharacterSound") or 0
	local timeSinceLastSound = os.clock() - lastCharacterSound
	local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and timeSinceLastSound > 0.7 then
		local soundList = assets.Sounds[soundType]:GetChildren()
		local newSound = soundList[math.random(#soundList)]:Clone()
		newSound.Parent = humanoidRootPart
		newSound:Play()
		debris:AddItem(newSound, newSound.TimeLength)
	end
	player:SetAttribute("LastCharacterSound", os.clock())
end)

repFootstep:Connect(function(player, material, foot: Sound, volume)
	if foot and foot:IsDescendantOf(player.Character) and player.Character then
		repFootstep:FireAllInRangeExcept(
			player,
			player.Character.HumanoidRootPart.Position,
			100,
			material,
			foot,
			volume
		)
	end
end)

local function DropGun(player, tool)
	if not tool then
		tool = player.Character:FindFirstChildWhichIsA("Tool")
	end
	if not config.gunDropping then
		return
	end

	if tool and tool:FindFirstChild("SPH_Weapon") then
		SpawnGun(tool, player.Character.HumanoidRootPart.CFrame * dropCFrame, player)
	else
		return
	end

	local newSound = assets.Sounds.Misc.WeaponDrop:Clone()
	newSound.Parent = player.Character.HumanoidRootPart
	newSound:Play()
	newSound.PlayOnRemove = true
	newSound:Destroy()
end

playerDropGun:Connect(DropGun)
assets.Events.DropGun.Event:Connect(DropGun)

playerToggleAttachment:Connect(function(player, attachmentType, toggle)
	local rig = player.Character.WeaponRig
	local weaponModel = player.Character.WeaponRig.Weapon:FindFirstChildWhichIsA("Model")
	local grip = weaponModel.Grip
	if weaponModel then
		if attachmentType == 0 and grip:FindFirstChild("Flashlight") then
			repToggleAttachment:FireToAllExcept(player, grip.Flashlight, toggle)
		elseif attachmentType == 1 and grip:FindFirstChild("Laser") then
			repToggleAttachment:FireToAllExcept(player, grip.Laser, toggle, player.Character)
		end
	end
end)

magGrab:Connect(function(player)
	if player.Character then
		local tool = player.Character:FindFirstChildWhichIsA("Tool")
		local humanoid = player.Character.Humanoid
		if not tool or not humanoid or humanoid.Health <= 0 then
			return
		end

		local rig = player.Character.WeaponRig
		local weaponModel = player.Character.WeaponRig.Weapon:FindFirstChildWhichIsA("Model")
		local wepStats = require(tool.SPH_Weapon.WeaponStats)

		local magPart: BasePart = wepStats.projectile ~= "Bullet" and weaponModel[wepStats.projectile]
			or weaponModel:FindFirstChild("Mag")
		if magPart then
			repMagGrab:FireToAllExcept(player, magPart)
		end
	end
end)

playerLean:Connect(function(player, leanDirection)
	if player.Character then
		local humanoid = player.Character:FindFirstChild("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end
		repLean:FireToAllExcept(player, player.Character, leanDirection)
	end
end)

--assets.Events.ToggleAttachment.OnServerEvent:Connect(function(player: Player, attachmentType:string, toggle:boolean)

--end)

print(warnPrefix .. "Main Server loaded successfully!")
