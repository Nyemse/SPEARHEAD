local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")
local debris = game:GetService("Debris")
local players = game:GetService("Players")
local tweenService = game:GetService("TweenService")
local testService = game:GetService("TestService")
local contextActionService = game:GetService("ContextActionService")
local collectionService = game:GetService("CollectionService")

local assets = replicatedStorage.SPH_Assets
local modules = assets.Modules
local animations = assets.Animations
local player = players.LocalPlayer
local toggleViewmodelSprint = assets.Events.ToggleViewmodelSprint

local character = script.Parent.Parent
local humanoid: Humanoid = character:WaitForChild("Humanoid")
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
local rootJoint = humanoidRootPart:WaitForChild("RootJoint")
local neckJoint
if humanoid.RigType == Enum.HumanoidRigType.R6 then
	neckJoint = character.Torso.Neck
else
	neckJoint = character.UpperTorso.Neck
end
local camera = workspace.CurrentCamera
if camera.CameraSubject ~= humanoid then
	camera.CameraSubject = humanoid
end
camera.CameraType = Enum.CameraType.Custom
if camera:FindFirstChild("WeaponRig") then
	camera.WeaponRig:Destroy()
end

local defaultFOV = 70

local weldMod = require(modules.WeldMod)
local bridgeNet = require(modules.BridgeNet)
local viewMod = require(modules.ViewMod)
local springMod = require(modules.SpringModule)
local hitFX = require(modules.HitFX)
local shellEjection = require(modules.ShellEjection)
local bulletHandler = require(modules.BulletHandler)
local callbacks = require(assets.Mods)
bulletHandler.Initialize(player)

local config = require(assets.GameConfig)
local warnPrefix = "【 SPEARHEAD 】 "
humanoid.WalkSpeed = config.walkSpeed

local sphWorkspace = workspace:WaitForChild("SPH_Workspace")
local shellFolder = sphWorkspace:WaitForChild("Shells")

local rayParams = RaycastParams.new()
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = true
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { character, camera, shellFolder }

local swaySpring = springMod.new()
local moveSpring = springMod.new()
local recoilSpring = springMod.new()
local gunRecoilSpring = springMod.new()

local bodyAnimRequest = bridgeNet.CreateBridge("BodyAnimRequest")
local switchWeapon = bridgeNet.CreateBridge("SwitchWeapon")
local playerFire = bridgeNet.CreateBridge("PlayerFire")
local playSound = bridgeNet.CreateBridge("PlaySound")
local repReload = bridgeNet.CreateBridge("Reload")
local repChamber = bridgeNet.CreateBridge("PlayerChamber")
local moveBolt = bridgeNet.CreateBridge("MoveBolt")
local switchFireMode = bridgeNet.CreateBridge("SwitchFireMode")
local playerDropGun = bridgeNet.CreateBridge("PlayerDropGun")
local playerToggleAttachment = bridgeNet.CreateBridge("PlayerToggleAttachment")
local repBoltOpen = bridgeNet.CreateBridge("RepBoltOpen")
local magGrab = bridgeNet.CreateBridge("MagGrab")

local fpThreshold = 0.6

local rollAngle = 0
local cameraRollAngle = 0
local cameraLeanRotation = 0

local depthOfField = game.Lighting:FindFirstChild("SPH_DoF")
	or (config.blurEffects and Instance.new("DepthOfFieldEffect", game.Lighting))
if depthOfField then
	depthOfField.Name = "SPH_DoF"
end

local holdingM1 = false
local cycled = true
local firstPerson = false
local equipping = false
local dead = false
local canFire = true
local viewmodelVisible = false
local blocked = false
local holdStance = 0
local holdAnim
local laserEnabled = false
local flashlightEnabled = false
local vehicleSeated = false
local ejected = true
local cancelReload = false
local chambering = false
local aimHeld = false
local aimTransitionPlaying = false
local airborne = false

local fireModes = {
	Safe = 0,
	Semi = 1,
	Auto = 2,
	Burst = 3,
	Manual = 4,
}
local curFireMode
local bulletsCurrentlyFired = 0

local equipped: Tool, wepStats, sprinting, gunAmmo, reloading, aiming, offset, freeLook, moving
local gunModel: Model
local freeLookOffset = CFrame.new()
local freeLookRotation = CFrame.new()
local aimingOffset = CFrame.new()
local aimTarget = CFrame.new()
local aimFOVTarget = camera.FieldOfView
local shakeCFrame = CFrame.new()
local bipodCFrame = CFrame.new()

local headRotationEventCooldown = 0

local pushbackOffset = 0

local hipRotation = Vector2.zero

local storageCFrame = CFrame.new(1000000, 0, 0) -- This is used for moving the viewmodel super far away.
-- Doing this to the viewmodel allows animations to be loaded, played, etc, while still having it out of view.

local loadedAnims = {}
local proneMoveAnim: AnimationTrack

local xHead, yHead, zHead
local cameraOffsetTarget = Vector3.zero

local defaultCameraMode = Enum.CameraMode.Classic

local sights = {}

local sightIndex = 1

local aimSensitivity = player:GetAttribute("SavedAimSensitivity") or config.defaultAimSensitivity
local proneViewmodelOffset = 0

local tempCameraRoll = 0

local laserDotUI = assets.HUD.LaserDotUI:Clone()
local laserDotPoint = Instance.new("Attachment")
laserDotPoint.Parent = workspace.Terrain
laserDotUI.Enabled = false
laserDotUI.Parent = laserDotPoint
--laserDotUI.AlwaysOnTop = true

local laserBeamFP = Instance.new("Beam")
laserBeamFP.Attachment1 = laserDotPoint
laserBeamFP.LightInfluence = 0
laserBeamFP.Brightness = 3
laserBeamFP.Segments = 1
laserBeamFP.Width0 = 0.02
laserBeamFP.Width1 = 0.02
laserBeamFP.FaceCamera = true
laserBeamFP.Transparency = NumberSequence.new(0.5)
laserBeamFP.Name = "FirstPersonLaser"
laserBeamFP.Parent = laserDotPoint
laserBeamFP.Enabled = false

local laserBeamTP = laserBeamFP:Clone()
laserBeamTP.Name = "ThirdPersonLaser"
laserBeamTP.Parent = laserDotPoint
laserBeamTP.Enabled = false

-- Disable default death sound
if humanoidRootPart:FindFirstChild("Died") then
	humanoidRootPart.Died.Volume = 0
end

-- Unlock the camera if lock first person for guns is enabled
if config.lockFirstPerson then
	player.CameraMode = Enum.CameraMode.Classic
end

-- Create new viewmodel
rig = viewMod.RigModel(player)

-- Create fake arms
local lArm = rig["Left Arm"]
local rArm = rig["Right Arm"]
lArm.Color = character["Left Arm"].Color
rArm.Color = character["Right Arm"].Color

for _, part in ipairs(rig:GetDescendants()) do
	if part.Name == "Skin" then
		if part.Parent.Name == "Left Arm" then
			part.Color = character["Left Arm"].Color
		elseif part.Parent.Name == "Right Arm" then
			part.Color = character["Right Arm"].Color
		end
	end
end

-- Set up an animator
local vmHuman = Instance.new("Humanoid", rig)
for _, state in ipairs(Enum.HumanoidStateType:GetEnumItems()) do
	if state == Enum.HumanoidStateType.None then
		continue
	end -- The 'None' state needs to be skipped because it cannot be disabled
	vmHuman:SetStateEnabled(state, false)
end

local vmAnimator = Instance.new("Animator", vmHuman)
local vmShirt = Instance.new("Shirt", rig)
local animBase = rig.AnimBase
animBase.CFrame = storageCFrame

rig.Parent = camera

local weaponRig = character:FindFirstChild("WeaponRig") or character:WaitForChild("WeaponRig", 20)
local characterAnimator: Animator = weaponRig:WaitForChild("AnimationController").Animator

local function PlayRepSound(soundName)
	if not dead then
		local soundToPlay = gunModel.Grip:FindFirstChild(soundName)
		if soundToPlay and equipped then
			if firstPerson then
				soundToPlay:Play()
			else
				local soundToPlay = soundToPlay:Clone()
				soundToPlay.Parent = humanoidRootPart
				soundToPlay:Play()
				debris:AddItem(soundToPlay, soundToPlay.TimeLength)
			end
			playSound:Fire(soundName, firstPerson)
		end
	end
end

local function IsLoaded()
	return not wepStats.openBolt and equipped.Chambered.Value or wepStats.openBolt and gunAmmo.MagAmmo.Value > 0
end

local function MoveBolt(direction: CFrame, silent: boolean)
	bulletHandler.MoveBolt(gunModel, wepStats, direction, gunAmmo.MagAmmo.Value)
	bulletHandler.MoveBolt(weaponRig.Weapon:FindFirstChildWhichIsA("Model"), wepStats, direction, gunAmmo.MagAmmo.Value)
	if gunAmmo.MagAmmo.Value <= 0 and not silent then
		PlayRepSound("Empty")
	end
	moveBolt:Fire(direction, gunAmmo.MagAmmo.Value)
end

local function ToggleADS(toggle)
	if wepStats and wepStats.ADSEnabled then
		local ADSTween
		if wepStats.aimTime then
			ADSTween = TweenInfo.new(
				wepStats.aimTime / 20,
				Enum.EasingStyle.Linear,
				Enum.EasingDirection.Out,
				0,
				false,
				wepStats.aimTime / 20
			)
		else
			ADSTween = TweenInfo.new(0.2, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0.2)
		end
		if not toggle then
			for _, child in pairs(gunModel:GetChildren()) do
				if child.Name == "REG" then
					tweenService:Create(child, ADSTween, { Transparency = 0 }):Play()
				elseif child.Name == "ADS" then
					tweenService:Create(child, ADSTween, { Transparency = 1 }):Play()
				end
			end
		elseif toggle then
			for _, child in pairs(gunModel:GetChildren()) do
				if child.Name == "REG" then
					tweenService:Create(child, ADSTween, { Transparency = 1 }):Play()
				elseif child.Name == "ADS" then
					tweenService:Create(child, ADSTween, { Transparency = 0 }):Play()
				end
			end
		end
	end
end

local function EjectShell()
	ejected = true
	if wepStats.shellEject and config.shellEjection then
		if firstPerson then
			shellEjection.ejectShell(player, equipped, gunModel)
		else
			shellEjection.ejectShell(player, equipped, weaponRig.Weapon:FindFirstChildWhichIsA("Model"))
		end
	end
end

local function GetThirdPersonGunModel()
	return weaponRig.Weapon:FindFirstChildWhichIsA("Model")
end

-- Stop an animation track that has already been loaded
local function StopAnimation(animName: string, transTime: number)
	if loadedAnims[animName] then
		if transTime then
			loadedAnims[animName]:Stop(transTime)
			loadedAnims[animName .. "ThirdPerson"]:Stop(transTime)
		else
			loadedAnims[animName]:Stop()
			loadedAnims[animName .. "ThirdPerson"]:Stop()
		end
	end
end

local function SwitchFireMode()
	local repitions = 0
	repeat
		repitions += 1
		curFireMode += 1
		if curFireMode > 4 then
			if wepStats.noSafety or true then
				curFireMode = 1
			else
				curFireMode = 0
				break
			end
		end
	until wepStats.fireSwitch[curFireMode] or repitions > 10
	switchFireMode:Fire(curFireMode)
end

local function UpdateAllBulletTransparency(bulletHolderPart: BasePart, transparency: number)
	for _, child in bulletHolderPart:GetChildren() do
		if child:IsA("BasePart") and string.sub(child.Name, 1, 6) == "Bullet" then
			child.Transparency = transparency
		end
	end
end

local function UpdateBulletTransparency(bulletHolderPart: BasePart, bulletNumber: number, transparency: number)
	local bulletName = "Bullet" .. bulletNumber

	for _, child in bulletHolderPart:GetChildren() do
		if child:IsA("BasePart") and child.Name == bulletName then
			child.Transparency = transparency
		end
	end
end

-- Play an animation or load it if it's not already
local function PlayAnimation(animName: string, parameters: table, animType: string, preload)
	parameters = parameters or {}
	local animObject = animName and animations:FindFirstChild(animName)
	local animToPlay, tpAnim
	if loadedAnims[animName] then
		animToPlay = loadedAnims[animName]
		tpAnim = loadedAnims[animName .. "ThirdPerson"]
	elseif animName and animObject then
		local newAnim = vmAnimator:LoadAnimation(animObject)
		newAnim.Looped = parameters.looped or false
		newAnim.Priority = parameters.priority or Enum.AnimationPriority.Action
		loadedAnims[animName] = newAnim

		local thirdPersonAnim: AnimationTrack = characterAnimator:LoadAnimation(animObject)
		thirdPersonAnim.Looped = parameters.looped or false
		thirdPersonAnim.Priority = parameters.priority or Enum.AnimationPriority.Action
		loadedAnims[animName .. "ThirdPerson"] = thirdPersonAnim

		-- Keyframe names
		newAnim.KeyframeReached:Connect(function(keyframeName)
			if gunModel.Grip:FindFirstChild(keyframeName) then
				PlayRepSound(keyframeName)
			end

			if keyframeName == "MagIn" then
				-- Bullet visibility
				local bulletHolderPart = wepStats.bulletHolder and gunModel:FindFirstChild(wepStats.bulletHolder)
				if bulletHolderPart then
					UpdateAllBulletTransparency(bulletHolderPart, 0)
				end

				repReload:Fire()
				--reloading = false

				if wepStats.magType > 1 then
					newAnim.DidLoop:Once(function()
						StopAnimation(animName)
					end)
				end
			elseif keyframeName == "ShellInsert" or keyframeName == "BulletInsert" then
				if cancelReload then -- Should reloading be canceled?
					cancelReload = false
					newAnim.Looped = false
					newAnim.Stopped:Once(function()
						if not equipped then
							return
						end
						StopAnimation(newAnim.Name)
						if not equipped.BoltReady.Value or wepStats.openBolt then
							PlayAnimation(wepStats.boltClose, { priority = Enum.AnimationPriority.Action2 })
						else
							reloading = false
						end
					end)
				elseif
					gunAmmo.MagAmmo.Value + 1 >= gunAmmo.MagAmmo.MaxValue or gunAmmo.ArcadeAmmoPool.Value - 1 <= 0
				then
					newAnim.DidLoop:Once(function()
						if not equipped then
							return
						end
						StopAnimation(newAnim.Name)
						if not equipped.BoltReady.Value or wepStats.operationType == 3 or wepStats.openBolt then
							PlayAnimation(wepStats.boltClose, { priority = Enum.AnimationPriority.Action2 })
						else
							reloading = false
						end
					end)
				elseif wepStats.openBolt then
					--PlayAnimation(wepStats.boltClose,{priority = Enum.AnimationPriority.Action2})
					--print(gunAmmo.MagAmmo.Value, gunAmmo.ArcadeAmmoPool.Value)
				end
				-- Bullet visibility
				local bulletHolderPart = wepStats.bulletHolder and gunModel:FindFirstChild(wepStats.bulletHolder)
				if bulletHolderPart then
					local bulletNumber = gunAmmo.MagAmmo.MaxValue - gunAmmo.MagAmmo.Value
					UpdateBulletTransparency(bulletHolderPart, bulletNumber, 0)
				end

				repReload:Fire()
			elseif keyframeName == "ClipInsertEnd" then
				local ammoNeeded = gunAmmo.MagAmmo.MaxValue - gunAmmo.MagAmmo.Value
				local clipSize = wepStats.clipSize or wepStats.magazineCapacity

				if ammoNeeded > 0 then
					StopAnimation(newAnim.Name)
					if ammoNeeded >= clipSize then
						PlayAnimation(wepStats.clipReloadAnim, {
							looped = true,
							speed = wepStats.reloadSpeedModifier,
							priority = Enum.AnimationPriority.Action2,
							transSpeed = 0.17,
						})
					else
						PlayAnimation(wepStats.reloadAnim, {
							speed = wepStats.reloadSpeedModifier,
							priority = Enum.AnimationPriority.Action2,
							transSpeed = 0.17,
						}, "Reload")
					end
				end

				--StopAnimation(newAnim.Name)
				--PlayAnimation(wepStats.reloadAnim,{speed = wepStats.reloadSpeedModifier,priority = Enum.AnimationPriority.Action2,transSpeed = 0.17},"Reload")
				--PlayAnimation(wepStats.clipReloadAnim,{looped = true,speed = wepStats.reloadSpeedModifier,priority = Enum.AnimationPriority.Action2,transSpeed = 0.17})
			elseif keyframeName == "ClipInsert" then
				repReload:Fire()
			elseif keyframeName == "SlideRelease" or keyframeName == "BoltClose" then
				repChamber:Fire()
				reloading = false
				MoveBolt(CFrame.new(), true)
			elseif keyframeName == "SlidePull" and equipped.Chambered.Value then
				EjectShell()
				--elseif keyframeName == "Equip" then
				--equipping = false
				--if firstPerson then viewmodelVisible = true end

				--local projectile = gunModel:FindFirstChild(wepStats.projectile)
				--if not IsLoaded() and projectile and wepStats.projectile ~= "Bullet" then
				--	projectile.LocalTransparencyModifier = 1
				--	for _, child in ipairs(projectile:GetDescendants()) do
				--		if child:IsA("BasePart") then
				--			child.LocalTransparencyModifier = 1
				--		end
				--	end
				--end
			elseif keyframeName == "Switch" and not reloading then
				SwitchFireMode()
			elseif keyframeName == "MagGrab" then
				if gunModel and wepStats.projectile ~= "Bullet" and gunModel:FindFirstChild(wepStats.projectile) then
					local projectile = gunModel:FindFirstChild(wepStats.projectile)
					projectile.LocalTransparencyModifier = 0
					for _, child in ipairs(projectile:GetDescendants()) do
						if child:IsA("BasePart") then
							child.LocalTransparencyModifier = 0
						end
					end
					local thirdPersonGunModel = GetThirdPersonGunModel()
					local projectile = thirdPersonGunModel:FindFirstChild(wepStats.projectile)
					projectile.LocalTransparencyModifier = 0
					for _, child in ipairs(projectile:GetDescendants()) do
						if child:IsA("BasePart") then
							child.LocalTransparencyModifier = 0
						end
					end
					magGrab:Fire()
				end
			elseif keyframeName == "BoltOpen" then
				repBoltOpen:Fire()
				if not ejected then
					EjectShell()
				end
			elseif keyframeName == "MagPouch" then
				-- Bullet visibility
				local bulletHolderPart = wepStats.bulletHolder and gunModel:FindFirstChild(wepStats.bulletHolder)
				if bulletHolderPart then
					UpdateAllBulletTransparency(bulletHolderPart, 0)
				end
			end
		end)

		newAnim.Stopped:Connect(function()
			if animType == "Equip" then
				--equipping = false
				--if firstPerson then viewmodelVisible = true end
			elseif animType == "Reload" then
				reloading = false
				if
					wepStats
					and gunModel
					and gunModel:FindFirstChild(wepStats.projectile)
					and equipped.Chambered.Value
				then
					local projectile = gunModel:FindFirstChild(wepStats.projectile)
					projectile.LocalTransparencyModifier = 0
					for _, child in ipairs(projectile:GetDescendants()) do
						if child:IsA("BasePart") then
							child.LocalTransparencyModifier = 0
						end
					end
				end
			end
		end)

		animToPlay = newAnim
		tpAnim = thirdPersonAnim
	end

	-- Don't play aiming animations if firstPersonAimAnim is false
	local playAnimFP = true
	if animType == "AimAnim" and not config.firstPersonAimAnim then
		playAnimFP = false
	end

	-- Play the animation if it isn't just being pre-loaded
	if animToPlay and not preload then
		if playAnimFP then
			animToPlay:Play(parameters.transSpeed or 0)
			animToPlay:AdjustSpeed(parameters.speed or 1)
		end
		tpAnim:Play(parameters.transSpeed or 0)
		tpAnim:AdjustSpeed(parameters.speed or 1)
	end

	-- Return the animation track and animation object that was just played or loaded
	return animToPlay, animObject
end

local function ChangeHoldStance(newStance)
	if aiming then
		return
	end
	if holdStance == newStance and holdAnim then
		StopAnimation(holdAnim.Name, 0.3)
		holdAnim = nil
		holdStance = 0
	else
		holdStance = newStance

		if holdAnim then
			StopAnimation(holdAnim.Name, 0.3)
		end

		local animToPlay
		if holdStance == 1 and wepStats.holdUpAnim then
			animToPlay = wepStats.holdUpAnim
		elseif holdStance == 2 and wepStats.patrolAnim then
			animToPlay = wepStats.patrolAnim
		elseif holdStance == 3 and wepStats.holdDownAnim then
			animToPlay = wepStats.holdDownAnim
		end

		if animToPlay then
			holdAnim =
				PlayAnimation(animToPlay, { looped = true, priority = Enum.AnimationPriority.Action, transSpeed = 0.3 })
			holdAnim:Play()
		elseif holdAnim then
			holdAnim = nil
		end
	end
end

local function ChamberAnim()
	local animNameToPlay
	if equipped.BoltReady.Value or curFireMode == fireModes.Manual then
		animNameToPlay = wepStats.boltChamber
	else
		animNameToPlay = wepStats.boltClose
	end

	if animNameToPlay then
		reloading = true
		chambering = true
		ChangeHoldStance(0)

		local playingAnim: AnimationTrack =
			PlayAnimation(animNameToPlay, { priority = Enum.AnimationPriority.Action2, transSpeed = 0.05 })
		playingAnim.Stopped:Once(function()
			chambering = false
		end)
	end
end

local function IdleAnim()
	PlayAnimation(wepStats.idleAnim, { looped = true, priority = Enum.AnimationPriority.Idle })
end

local function EquipAnim()
	local animTrack: AnimationTrack = PlayAnimation(
		wepStats.equipAnim,
		{ priority = Enum.AnimationPriority.Action2, looped = false, speed = (wepStats.equipSpeedModifier or 1) },
		"Equip"
	)

	-- Wait until the animation has loaded and started moving, or wait until 20 attempts have been made.
	local loadAttempts = 0
	while loadAttempts < 20 and (animTrack.Length == 0 or animBase.AnimBase_Grip.Transform == CFrame.new()) do
		loadAttempts += 1
		task.wait()
	end

	if firstPerson then
		viewmodelVisible = true
	end

	local projectile = gunModel:FindFirstChild(wepStats.projectile)
	if (wepStats.openBolt or not equipped.Chambered.Value) and projectile and wepStats.projectile ~= "Bullet" then
		projectile.LocalTransparencyModifier = 1
		for _, child in ipairs(projectile:GetDescendants()) do
			if child:IsA("BasePart") then
				child.LocalTransparencyModifier = 1
			end
		end
	end
end

local function ToggleAiming(toggle)
	if reloading and toggle and not config.canReloadWhileAiming then
		return
	end

	character:SetAttribute("Aiming", toggle)
	if toggle then
		ChangeHoldStance(0)
		aiming = true
		if wepStats.ADSEnabled and wepStats.ADSEnabled[sightIndex] then
			ToggleADS(true)
		else
			ToggleADS(false)
		end
		userInputService.MouseDeltaSensitivity = aimSensitivity
		PlayRepSound("AimUp")

		--tweenService:Create(camera,TweenInfo.new(wepStats.aimTime),{FieldOfView = wepStats.aimFovDefault or defaultFOV}):Play()

		if not config.lockFirstPerson then
			player.CameraMode = Enum.CameraMode.LockFirstPerson
		end

		if wepStats.aimAnim then
			local transTime = wepStats.aimTime / 4
			PlayAnimation(
				wepStats.aimAnim,
				{ looped = true, priority = Enum.AnimationPriority.Action, transSpeed = transTime },
				"AimAnim"
			)
			--aimTransitionPlaying = true

			--if config.firstPersonAimAnim then
			--	delay(transTime, function()
			--		aimTransitionPlaying = false
			--	end)
			--else
			--	aimTransitionPlaying = false
			--end
		end

		if config.proceduralAimAnim then
			tempCameraRoll = 13
			task.delay(0.1, function()
				if aiming == toggle then
					tempCameraRoll = 0
				end
			end)

			swaySpring:shove(Vector3.new(0, -1, 0))
		end
	else
		aiming = false
		ToggleADS(false)
		userInputService.MouseDeltaSensitivity = 1
		PlayRepSound("AimDown")
		local aimOutTime
		if wepStats then
			aimOutTime = wepStats.aimTime / 2
		else
			aimOutTime = 0.3
		end
		tweenService:Create(camera, TweenInfo.new(aimOutTime), { FieldOfView = defaultFOV }):Play()
		if not config.lockFirstPerson then
			player.CameraMode = defaultCameraMode
		end

		if wepStats then
			StopAnimation(wepStats.aimAnim, wepStats.aimTime / 6)
		end

		if config.proceduralAimAnim then
			tempCameraRoll = 10
			task.delay(0.1, function()
				if aiming == toggle then
					tempCameraRoll = 0
				end
			end)

			swaySpring:shove(Vector3.new(0, -1, 0))
		end
	end
end

local function ReloadAnim()
	if not equipped then
		return
	end

	if not config.canReloadWhileAiming and aiming then
		ToggleAiming(false)
	end

	cancelReload = false

	ChangeHoldStance(0)
	reloading = true

	if
		wepStats.operationType == 3
		or (wepStats.operationType == 2 and gunAmmo.MagAmmo.Value <= 0 and not equipped.Chambered.Value)
	then
		local boltOpenTrack = PlayAnimation(
			wepStats.boltOpen,
			{ speed = wepStats.reloadSpeedModifier, priority = Enum.AnimationPriority.Action2, transSpeed = 0.17 }
		)
		if not boltOpenTrack then
			warn(
				warnPrefix
					.. "To use operation type "
					.. wepStats.operationType
					.. ", a 'boltOpen' animation is required."
			)
			reloading = false
			return
		end
		boltOpenTrack.Stopped:Once(function()
			if
				wepStats.magType == 3
				and (gunAmmo.MagAmmo.MaxValue - gunAmmo.MagAmmo.Value) >= (wepStats.clipSize or wepStats.magazineCapacity)
				and gunAmmo.ArcadeAmmoPool.Value >= (wepStats.clipSize or wepStats.magazineCapacity)
			then
				-- Clip insert
				local clipReloadTrack = PlayAnimation(wepStats.clipReloadAnim, {
					looped = true,
					speed = wepStats.reloadSpeedModifier,
					priority = Enum.AnimationPriority.Action2,
					transSpeed = 0.17,
				})
				--clipReloadTrack.Stopped:Once(function()
				--	if gunAmmo.MagAmmo.Value + 1 < gunAmmo.MagAmmo.MaxValue and gunAmmo.ArcadeAmmoPool.Value > 0 then
				--		ReloadAnim()
				--	end
				--end)
				--clipReloadTrack.Stopped:Connect(function()

				--end)
			else
				-- Bullet insert
				local bulletInsert = PlayAnimation(wepStats.reloadAnim, {
					speed = wepStats.reloadSpeedModifier,
					priority = Enum.AnimationPriority.Action2,
					transSpeed = 0.17,
					looped = true,
				}, "Reload")
				if wepStats.magType > 1 then
					bulletInsert.Looped = true
				end
			end
		end)
	else
		local reloadAnim = PlayAnimation(
			wepStats.reloadAnim,
			{ speed = wepStats.reloadSpeedModifier, priority = Enum.AnimationPriority.Action2, transSpeed = 0.17 },
			"Reload"
		)

		-- Auto chamber code
		if wepStats.autoChamber then
			reloadAnim.Stopped:Once(function()
				if equipped and (not equipped.Chambered.Value or wepStats.openBolt) then
					reloading = true
					local animNameToPlay
					if equipped.BoltReady.Value then
						animNameToPlay = wepStats.boltChamber
					else
						animNameToPlay = wepStats.boltClose
					end
					PlayAnimation(animNameToPlay, { priority = Enum.AnimationPriority.Action2, transSpeed = 0.05 })
				end
			end)
		end
	end
end

-- Makes the viewmodel visible and refreshes its appearance
local function RefreshViewmodel()
	if firstPerson and not equipping then
		viewmodelVisible = true
	end

	local plrShirt = character:FindFirstChildWhichIsA("Shirt")
	if plrShirt then
		vmShirt.ShirtTemplate = plrShirt.ShirtTemplate
	end

	lArm.Color = character["Left Arm"].Color
	rArm.Color = character["Right Arm"].Color

	for _, part in ipairs(rig:GetDescendants()) do
		if part.Name == "Skin" then
			if part.Parent.Name == "Left Arm" then
				part.Color = character["Left Arm"].Color
			elseif part.Parent.Name == "Right Arm" then
				part.Color = character["Right Arm"].Color
			end
		end
	end

	IdleAnim()

	if callbacks.onViewmodelRefresh then
		callbacks.onViewmodelRefresh(player, rig)
	end
end

local function CanOpenBipod()
	if gunModel:FindFirstChild("BipodBase") and wepStats.bipodHeight then
		local bipodBase: BasePart = gunModel:FindFirstChild("BipodBase")
		local groundCheck = workspace:Raycast(bipodBase.Position, Vector3.new(0, -wepStats.bipodHeight, 0), rayParams)
		if groundCheck then
			return groundCheck.Position,
				bipodBase,
				(bipodBase.Position - groundCheck.Position).Magnitude,
				wepStats.bipodHeight
		end
	end
end

-- Remove rig and reset head orientation
local function ResetHead()
	viewmodelVisible = false
end

local function GetSineOffset(addition: number)
	return math.sin(tick() * addition * 1.3) * 0.3
end

local function LerpNumber(number: number, target: number, speed: number)
	return number + (target - number) * speed
end

local recoilUpdateCD = 0
local fps = 0
local extraCamRoll = 0

-- Update the viewmodel's CFrame
local function UpdateViewmodelPosition(dt: number)
	fps = 1 / dt

	recoilUpdateCD -= dt

	-- Move the viewmodel to the camera's CFrame position and add the gun's offset
	animBase.CFrame = CFrame.new((camera.CFrame * offset).Position)

	-- Check if freelook is on and don't rotate the viewmodel if it is
	if not freeLook then
		animBase.CFrame *= camera.CFrame - camera.CFrame.Position
	else
		animBase.CFrame *= freeLookRotation
	end

	-- Move gunmodel up while prone
	if character:GetAttribute("Stance") == "Prone" and not equipped:GetAttribute("BipodEnabled") then
		proneViewmodelOffset = LerpNumber(proneViewmodelOffset, 0.2, 0.1)
	else
		proneViewmodelOffset = LerpNumber(proneViewmodelOffset, 0, 0.1)
	end
	animBase.CFrame *= CFrame.new(0, proneViewmodelOffset, 0)

	-- Freelook recovery
	local freelookRecovery = 0.2
	freeLookOffset = freeLookOffset:Lerp(CFrame.new(), freelookRecovery * dt * 60)
	animBase.CFrame *= freeLookOffset:Inverse()

	-- Bipod offset
	if equipped:GetAttribute("BipodEnabled") then
		local bipodPoint, bipodPart, bipodDistance, bipodMaxDistance = CanOpenBipod()
		if bipodPoint and bipodPart then
			bipodCFrame = bipodCFrame:Lerp(CFrame.new(0, (bipodMaxDistance - bipodDistance * 2) - 0.2, 0), 0.2)
		else
			bipodCFrame = bipodCFrame:Lerp(CFrame.new(), 0.2)
			equipped:SetAttribute("BipodEnabled", false)
			if gunModel.Grip:FindFirstChild("Bipod") then
				gunModel.Grip.Bipod:Play()
			end
		end
	else
		bipodCFrame = bipodCFrame:Lerp(CFrame.new(), 0.2)
	end
	animBase.CFrame *= bipodCFrame

	-- Aiming
	local aimPart: BasePart = gunModel:FindFirstChild("AimPart" .. sightIndex) or gunModel.AimPart
	aimTarget = aimPart.CFrame:ToObjectSpace(camera.CFrame)
	if not aimTransitionPlaying then
		if aiming then
			aimingOffset = aimingOffset:Lerp(aimTarget, (0.7 / wepStats.aimTime) * 0.3 * dt * 60)
		else
			aimingOffset = aimingOffset:Lerp(CFrame.new(), (0.7 / wepStats.aimTime) * 0.2 * dt * 60)
		end
	end

	-- Apply aiming offset
	if freeLook then -- Only apply position offset
		animBase.CFrame *= CFrame.new(aimingOffset.Position)
	else
		animBase.CFrame *= aimingOffset
	end

	-- Check if gun is too close to a wall
	--local rayDistance = (animBase.CFrame.Position - gunModel.Grip.Muzzle.WorldCFrame.Position).Magnitude + 1
	local rayDistance = wepStats.gunLength
	local originCFrame = firstPerson and animBase.CFrame or weaponRig.AnimBase.CFrame
	local newRay = workspace:Raycast(originCFrame.Position, originCFrame.LookVector * rayDistance, rayParams)
	if newRay and newRay.Instance and not newRay.Instance:HasTag("SPH_NoCollide") then
		local distance = rayDistance - (originCFrame.Position - newRay.Position).Magnitude
		if config.pushBackViewmodel and distance > 0 then
			local tempDist = distance
			if blocked then
				tempDist /= 2
			end
			pushbackOffset = LerpNumber(pushbackOffset, tempDist, 0.2 * 60 * dt)
		else
			pushbackOffset = LerpNumber(pushbackOffset, 0, 0.2 * 60 * dt)
		end

		if config.raiseGunAtWall then
			if distance >= wepStats.maxPushback then
				if not blocked then
					ChangeHoldStance(0)
					PlayAnimation(
						wepStats.holdUpAnim,
						{ looped = true, priority = Enum.AnimationPriority.Action, transSpeed = 0.3 }
					)
					blocked = true
					if aiming then
						ToggleAiming(false)
					end
				end
			elseif blocked then
				StopAnimation(wepStats.holdUpAnim, 0.3)
				blocked = false
				if aimHeld and not aiming and firstPerson and not sprinting then
					ToggleAiming(true)
				end
			end
		end
	else
		if blocked then
			StopAnimation(wepStats.holdUpAnim, 0.3)

			blocked = false
			if aimHeld and not aiming and firstPerson and not sprinting then
				ToggleAiming(true)
			end
		end

		pushbackOffset = LerpNumber(pushbackOffset, 0, 0.2 * 60 * dt)
	end
	animBase.CFrame *= CFrame.new(0, 0, pushbackOffset)

	-- Update strafing roll
	local relativeVelocity = humanoidRootPart.CFrame:VectorToObjectSpace(humanoidRootPart.Velocity)
	local targetRollAngle = 0
	if not aiming then
		targetRollAngle = math.clamp(-relativeVelocity.X, -config.maxStrafeRoll, config.maxStrafeRoll)
	end

	if config.cameraTilting then
		targetRollAngle /= 2
	end
	rollAngle = LerpNumber(rollAngle, targetRollAngle, 0.07 * dt * 60)
	animBase.CFrame *= CFrame.Angles(0, 0, math.rad(rollAngle))

	extraCamRoll = LerpNumber(extraCamRoll, tempCameraRoll, 0.1 * dt * 60)
	animBase.CFrame *= CFrame.Angles(0, 0, math.rad(extraCamRoll))

	local mouseDelta = userInputService:GetMouseDelta()

	-- Update hipfire movement
	local tempHipRotation = hipRotation
	if config.hipfireMove and (not aiming or aiming and config.offCenterAiming) then
		local maxX = config.hipfireMoveX
		local maxY = config.hipfireMoveY
		if aiming then
			maxX /= 4
			maxY /= 4
		end
		local xRotation = math.clamp(tempHipRotation.X - mouseDelta.X * config.hipfireMoveSpeed * dt * 60, -maxX, maxX)
		local yRotation = math.clamp(tempHipRotation.Y - mouseDelta.Y * config.hipfireMoveSpeed * dt * 60, -maxY, maxY)
		tempHipRotation = Vector2.new(xRotation, yRotation)
		hipRotation = tempHipRotation
	else
		hipRotation = hipRotation:Lerp(Vector2.zero, 0.3)
	end
	animBase.CFrame *= CFrame.Angles(math.rad(hipRotation.Y), math.rad(hipRotation.X), 0)

	-- Update rotational sway
	swaySpring:shove(Vector3.new(-mouseDelta.X / 500, mouseDelta.Y / 200, 0))
	local updatedSway = swaySpring:update(dt)
	animBase.CFrame *= CFrame.new(updatedSway.X, updatedSway.Y, 0)

	-- Update breathing
	local tickTime = tick() * 0.15
	local tempDist = config.breathingDist
	if aiming then
		tempDist *= config.breathingAimMultiplier
	end
	animBase.CFrame *= CFrame.new(
		tempDist * math.sin(tickTime * config.breathingSpeed / 2),
		tempDist * math.sin(tickTime * config.breathingSpeed),
		0
	)

	-- Update recoil
	--local recoilStats = wepStats.recoil
	--local gunRecoil = wepStats.gunRecoil
	local updatedRecoil = recoilSpring.Position
	local updatedGunRecoil = gunRecoilSpring:update(dt)
	if recoilUpdateCD <= 0 then
		recoilUpdateCD = 1 / 60
		local currentFPS = 1 / dt
		local dtMult = (currentFPS / 60) - 1
		dtMult = dtMult / 2
		updatedRecoil = recoilSpring:update(0.016 + (0.016 * dtMult))
	end

	animBase.CFrame *= CFrame.Angles(math.rad(updatedGunRecoil.X), math.rad(updatedGunRecoil.Y), 0)
	animBase.CFrame *= CFrame.new(0, 0, updatedGunRecoil.Z)
	camera.CFrame *= CFrame.Angles(math.rad(updatedRecoil.X), math.rad(updatedRecoil.Y), math.rad(updatedRecoil.Z))

	-- Low health shaking effect
	if config.lowHealthEffects then
		if humanoid.Health < 35 then
			local timeStamp = os.clock() * 5
			local dampening = 50
			local randomShakeCFrame = CFrame.new(
				math.noise(timeStamp, 0, 0) / dampening,
				math.noise(0, timeStamp, 0) / dampening,
				math.noise(0, 0, timeStamp) / dampening
			)
			shakeCFrame = randomShakeCFrame
		else
			shakeCFrame = shakeCFrame:Lerp(CFrame.new(), 0.1) -- Return to normal once health is high enough
		end
		animBase.CFrame *= shakeCFrame
	end

	-- Viewmodel visibility
	if not viewmodelVisible then
		animBase.CFrame *= storageCFrame
	end
end

local function ChangeDoF(fInt, fDist, fRad, nInt)
	tweenService
		:Create(depthOfField, TweenInfo.new(0.2), {
			FarIntensity = fInt,
			FocusDistance = fDist,
			InFocusRadius = fRad,
			NearIntensity = nInt,
		})
		:Play()
end

-- Toggle spring speed
local function ToggleSprint(toggle: boolean)
	if toggle then
		if aiming then
			ToggleAiming(false)
		end
		ChangeHoldStance(0)
		userInputService.MouseDeltaSensitivity = 1
		holdingM1 = false
		if wepStats then
			PlayAnimation(
				wepStats.sprintAnim,
				{ looped = true, priority = Enum.AnimationPriority.Action, transSpeed = 0.25 }
			)
		end

		if depthOfField then
			ChangeDoF(0, 6, 0, 0.3)
		end
	elseif wepStats then
		if wepStats then
			StopAnimation(wepStats.sprintAnim, 0.25)
		end

		if depthOfField then
			ChangeDoF(0, 0, 0, 0)
		end
	end
end

local function HandleInput(actionName, inputState, inputObject)
	local inputBegan = Enum.UserInputState.Begin
	local inputEnded = Enum.UserInputState.End

	if equipped then -- Gun inputs
		if actionName == "SPH_Trigger" then
			if inputState == inputBegan then -- Holding M1
				cancelReload = true
				if not (sprinting or reloading) then -- Detect mouse click
					holdingM1 = true

					if
						not IsLoaded()
						and not (
							equipped:GetAttribute("FireMode") == fireModes.Manual
							and equipped:GetAttribute("MagAmmo") > 0
						)
					then
						PlayRepSound("Click")
					end
				end
			else -- No longer holding M1
				holdingM1 = false
				canFire = true
				bulletsCurrentlyFired = 0
			end
		elseif actionName == "SPH_DropGun" and inputState == inputBegan then -- Gun drop
			Unequip(equipped)
			playerDropGun:Fire()
		elseif actionName == "SPH_Reload" and inputState == inputBegan and not reloading and cycled then -- Reload
			if wepStats.infiniteAmmo or gunAmmo.ArcadeAmmoPool.Value > 0 then
				if wepStats.openBolt and gunAmmo.MagAmmo.Value < gunAmmo.MagAmmo.MaxValue then
					ReloadAnim()
				else
					if
						(wepStats.operationType == 4 and equipped.Chambered.Value)
						or (wepStats.operationType == 3 and gunAmmo.MagAmmo.MaxValue > 1 and gunAmmo.MagAmmo.Value + 1 >= gunAmmo.MagAmmo.MaxValue)
						or (wepStats.operationType == 2 and gunAmmo.MagAmmo.Value >= gunAmmo.MagAmmo.MaxValue)
					then
						return
					end
					ReloadAnim()
				end
			end
		elseif actionName == "SPH_HoldAim" then
			if not userInputService.TouchEnabled and not config.toggleAiming then -- Hold aiming
				if inputState == inputBegan and firstPerson and not blocked and not sprinting then
					aimHeld = true
					ToggleSprint(false)
					--if stance == 0 then ChangeWalkSpeed(config.walkSpeed) end
					ToggleAiming(true)
				elseif aiming then -- Not aiming
					aimHeld = false
					ToggleAiming(false)
				end
			elseif inputState == inputBegan then -- Mobile and toggle aiming
				if firstPerson and not blocked and not aiming and not sprinting then
					aimHeld = true
					ToggleSprint(false)
					--if stance == 0 then ChangeWalkSpeed(config.walkSpeed) end
					ToggleAiming(true)
				else
					aimHeld = false
					ToggleAiming(false)
				end
			end
		elseif actionName == "SPH_Chamber" and inputState == inputBegan and not reloading and cycled then -- Chambering
			ChamberAnim()
		elseif
			actionName == "SPH_SwitchSights"
			and inputState == inputBegan
			and aiming
			and gunModel:FindFirstChild("AimPart2")
		then -- Switch sights
			local tempIndex = sightIndex
			tempIndex += 1
			if gunModel:FindFirstChild("AimPart" .. tempIndex) then
				sightIndex = tempIndex
				PlayRepSound("AimUp")
			else
				sightIndex = 1
				PlayRepSound("AimDown")
			end
			if wepStats.ADSEnabled and wepStats.ADSEnabled[sightIndex] then
				ToggleADS(true)
			else
				ToggleADS(false)
			end
		elseif actionName == "SPH_Freelook" then -- Freelook
			if inputState == inputBegan then -- Holding
				freeLook = true
				humanoid.AutoRotate = false
				freeLookRotation = camera.CFrame - camera.CFrame.Position
			else -- Stopped holding
				freeLook = false
				freeLookOffset = freeLookRotation:ToObjectSpace(camera.CFrame)
				freeLookOffset = freeLookOffset - freeLookOffset.Position
				humanoid.AutoRotate = true
			end
		elseif actionName == "SPH_HoldUp" and inputState == inputBegan and not reloading then -- Hold stance up
			ChangeHoldStance(1)
		elseif actionName == "SPH_HoldPatrol" and inputState == inputBegan and not reloading then -- Hold stance patrol
			ChangeHoldStance(2)
		elseif actionName == "SPH_HoldDown" and inputState == inputBegan and not reloading then -- Hold stance down
			ChangeHoldStance(3)
		elseif actionName == "SPH_SwitchFireMode" and inputState == inputBegan then -- Switch fire mode
			PlayAnimation(wepStats.switchAnim, { transSpeed = 0.2 })
		elseif
			actionName == "SPH_ToggleLaser"
			and inputState == inputBegan
			and gunModel.Grip:FindFirstChild("Laser")
		then
			laserEnabled = not laserEnabled
			if not firstPerson then
				laserBeamTP.Enabled = true
			end
			PlayRepSound("Button")
			playerToggleAttachment:Fire(1, laserEnabled)
			laserDotUI.Dot.ImageColor3 = gunModel.Grip.Laser.Color.Value
		elseif actionName == "SPH_ToggleFlashlight" and inputState == inputBegan then
			local flashlight = gunModel.Grip:FindFirstChild("Flashlight")
			if flashlight then
				local light = flashlight:FindFirstChildWhichIsA("Light")
				flashlightEnabled = not flashlightEnabled
				light.Enabled = flashlightEnabled
				PlayRepSound("Button")
				playerToggleAttachment:Fire(0, light.Enabled)

				if not flashlightEnabled then
					weaponRig.Weapon
						:FindFirstChildWhichIsA("Model").Grip.Flashlight
						:FindFirstChildWhichIsA("Light").Enabled =
						false
				elseif not firstPerson then
					weaponRig.Weapon
						:FindFirstChildWhichIsA("Model").Grip.Flashlight
						:FindFirstChildWhichIsA("Light").Enabled =
						true
				end
			end
		elseif actionName == "SPH_ToggleSuppressor" and inputState == inputBegan then
			local suppressor: BasePart = gunModel:FindFirstChild("Suppressor")
			local suppressedFireSound = gunModel.Grip:FindFirstChild("SuppressedFire")
			if suppressor and suppressedFireSound then
				if gunModel:GetAttribute("SuppressorOn") then
					assets.Events.ToggleAttachment:FireServer("Suppressor", false)
					suppressor.Transparency = 1
					--gunModel.Grip.Click:Play()
				else
					assets.Events.ToggleAttachment:FireServer("Suppressor", true)
					suppressor.Transparency = 0
					--gunModel.Grip.Click:Play()
				end
			end
		elseif actionName == "SPH_ToggleBipod" and inputState == inputBegan then
			local bipodBase = gunModel:FindFirstChild("BipodBase")

			if bipodBase and wepStats.bipodHeight then
				if not equipped:GetAttribute("BipodEnabled") and CanOpenBipod() then
					equipped:SetAttribute("BipodEnabled", true)
					if gunModel.Grip:FindFirstChild("Bipod") then
						gunModel.Grip.Bipod:Play()
					end
				else
					equipped:SetAttribute("BipodEnabled", false)
					if gunModel.Grip:FindFirstChild("Bipod") then
						gunModel.Grip.Bipod:Play()
					end
				end
			end
		end
	end
end

local function BindAiming()
	contextActionService:BindActionAtPriority(
		"SPH_HoldAim",
		HandleInput,
		config.mobileButtons,
		config.gunInputPriority,
		unpack(config.aimGun)
	)
	contextActionService:SetTitle("SPH_HoldAim", "Aim")
	contextActionService:SetPosition("SPH_HoldAim", UDim2.fromScale(0.24, 0.3))
end

local function UnbindAiming()
	contextActionService:UnbindAction("SPH_HoldAim")
end

local function BindGunInputs() -- Bind inputs for a gun
	contextActionService:BindActionAtPriority(
		"SPH_Trigger",
		HandleInput,
		config.mobileButtons,
		config.gunInputPriority,
		unpack(config.fireGun)
	)
	contextActionService:BindActionAtPriority(
		"SPH_DropGun",
		HandleInput,
		false,
		config.gunInputPriority,
		unpack(config.dropKey)
	)
	contextActionService:BindActionAtPriority(
		"SPH_Reload",
		HandleInput,
		config.mobileButtons,
		config.gunInputPriority,
		unpack(config.keyReload)
	)
	contextActionService:BindActionAtPriority(
		"SPH_Chamber",
		HandleInput,
		false,
		config.gunInputPriority,
		unpack(config.keyChamber)
	)
	contextActionService:BindActionAtPriority(
		"SPH_SwitchSights",
		HandleInput,
		false,
		config.gunInputPriority,
		unpack(config.sightSwitch)
	)
	contextActionService:BindActionAtPriority(
		"SPH_Freelook",
		HandleInput,
		false,
		config.gunInputPriority,
		unpack(config.freeLook)
	)
	contextActionService:BindActionAtPriority(
		"SPH_HoldUp",
		HandleInput,
		false,
		config.gunInputPriority,
		unpack(config.holdUp)
	)
	contextActionService:BindActionAtPriority(
		"SPH_HoldPatrol",
		HandleInput,
		false,
		config.gunInputPriority,
		unpack(config.holdPatrol)
	)
	contextActionService:BindActionAtPriority(
		"SPH_HoldDown",
		HandleInput,
		false,
		config.gunInputPriority,
		unpack(config.holdDown)
	)
	contextActionService:BindActionAtPriority(
		"SPH_SwitchFireMode",
		HandleInput,
		false,
		config.gunInputPriority,
		unpack(config.switchFireMode)
	)
	contextActionService:BindActionAtPriority(
		"SPH_ToggleLaser",
		HandleInput,
		false,
		config.gunInputPriority,
		unpack(config.toggleLaser)
	)
	contextActionService:BindActionAtPriority(
		"SPH_ToggleFlashlight",
		HandleInput,
		false,
		config.gunInputPriority,
		unpack(config.toggleFlashlight)
	)
	contextActionService:BindActionAtPriority(
		"SPH_ToggleSuppressor",
		HandleInput,
		false,
		config.gunInputPriority,
		unpack(config.toggleSuppressor)
	)
	contextActionService:BindActionAtPriority(
		"SPH_ToggleBipod",
		HandleInput,
		false,
		config.gunInputPriority,
		unpack(config.toggleBipod)
	)

	if firstPerson then
		BindAiming()
	end

	contextActionService:SetTitle("SPH_Trigger", "Fire")
	contextActionService:SetPosition("SPH_Trigger", UDim2.fromScale(0.3, 0.6))

	contextActionService:SetTitle("SPH_Reload", "Reload")
	contextActionService:SetPosition("SPH_Reload", UDim2.fromScale(0, 0.6))
end

local function UnbindGunInputs() -- Remove gun inputs
	contextActionService:UnbindAction("SPH_Trigger")
	contextActionService:UnbindAction("SPH_DropGun")
	contextActionService:UnbindAction("SPH_Reload")
	contextActionService:UnbindAction("SPH_HoldAim")
	contextActionService:UnbindAction("SPH_Chamber")
	contextActionService:UnbindAction("SPH_SwitchSights")
	contextActionService:UnbindAction("SPH_Freelook")
	contextActionService:UnbindAction("SPH_HoldUp")
	contextActionService:UnbindAction("SPH_HoldPatrol")
	contextActionService:UnbindAction("SPH_HoldDown")
	contextActionService:UnbindAction("SPH_SwitchFireMode")
	contextActionService:UnbindAction("SPH_ToggleLaser")
	contextActionService:UnbindAction("SPH_ToggleFlashlight")
	contextActionService:UnbindAction("SPH_ToggleSuppressor")
	contextActionService:UnbindAction("SPH_ToggleBipod")
end

humanoid.Died:Connect(function()
	dead = true
	switchWeapon:Fire()
	equipped = nil
	wepStats = nil
	userInputService.MouseIconEnabled = true
	ToggleAiming(false)
	viewmodelVisible = false
	animBase.CFrame = storageCFrame

	UnbindGunInputs()

	if config.useDeathCameraSubject then
		repeat
			task.wait()
		until humanoid.Parent ~= character
		camera.CameraSubject = humanoid
	end

	if rig then
		rig:Destroy()
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = nil
end)

function Unequip(tool) -- Unequip a gun (Does not remove it from the player's character)
	animBase.CFrame = storageCFrame

	switchWeapon:Fire()
	if tool == equipped then
		equipped = nil
		wepStats = nil
	end
	userInputService.MouseIconEnabled = true
	ToggleAiming(false)
	viewmodelVisible = false

	-- Stop animations
	for _, track in ipairs(vmAnimator:GetPlayingAnimationTracks()) do
		track:Stop()
	end

	for _, track in ipairs(characterAnimator:GetPlayingAnimationTracks()) do
		track:Stop()
	end

	if config.lockFirstPerson then
		player.CameraMode = Enum.CameraMode.Classic
	end

	sights = {}

	freeLook = false
	freeLookOffset = freeLookRotation:ToObjectSpace(camera.CFrame)
	freeLookOffset = freeLookOffset - freeLookOffset.Position
	humanoid.AutoRotate = true

	if depthOfField then
		ChangeDoF(0, 0, 0, 0)
	end

	holdStance = 0
	holdAnim = nil

	laserEnabled = false
	flashlightEnabled = false
	laserDotUI.Enabled = false

	laserBeamFP.Enabled = false
	laserBeamTP.Enabled = false

	aimTransitionPlaying = false

	UnbindGunInputs()

	if animBase:FindFirstChild("AnimBase_Grip") then
		animBase.AnimBase_Grip:Destroy()
	end
end

local function GetRotationBetween(u, v, axis)
	local dot, uxv = u:Dot(v), u:Cross(v)
	if dot < -0.99999 then
		return CFrame.fromAxisAngle(axis, math.pi)
	end
	return CFrame.new(0, 0, 0, uxv.x, uxv.y, uxv.z, 1 + dot)
end

-- Equip function
character.ChildAdded:Connect(function(newChild)
	if newChild:FindFirstChild("SPH_Weapon") and not assets.WeaponModels:FindFirstChild(newChild.Name) then
		warn(warnPrefix .. "No gun model could be found for '" .. newChild.Name .. "'")
		return
	end

	if
		newChild:FindFirstChild("SPH_Weapon")
		and not dead
		and (not humanoid.Sit or humanoid.Sit and not vehicleSeated)
	then
		-- Reset variables
		reloading = false
		userInputService.MouseIconEnabled = false
		hipRotation = Vector2.zero
		equipping = true
		blocked = false
		laserEnabled = false
		cycled = true
		chambering = false

		switchWeapon:Fire(newChild)

		-- Setup new gun
		equipped = newChild
		wepStats = require(equipped.SPH_Weapon.WeaponStats)
		recoilSpring.Damping = wepStats.recoil.damping
		recoilSpring.Speed = wepStats.recoil.speed
		gunRecoilSpring.Damping = wepStats.gunRecoil.damping
		gunRecoilSpring.Speed = wepStats.gunRecoil.speed
		offset = wepStats.viewmodelOffset
		aimFOVTarget = wepStats.aimFovDefault or defaultFOV
		freeLookOffset = CFrame.new()

		-- Preload prone move animation
		proneMoveAnim = wepStats.proneMoveAnim
			and PlayAnimation(
				wepStats.proneMoveAnim,
				{ looped = true, priority = Enum.AnimationPriority.Movement, transSpeed = 1 },
				"ProneMove",
				true
			)

		if not wepStats.operationType then
			wepStats.operationType = 1
		end

		if type(wepStats.operationType) == "string" then
			wepStats.operationType = 1
		end
		if not wepStats.magType then
			wepStats.magType = 1
		end

		-- Destroy old gun model
		local oldGun = rig.Weapon:FindFirstChildWhichIsA("Model")
		if oldGun then
			oldGun:Destroy()
		end

		-- New gun model
		local gun = assets.WeaponModels:FindFirstChild(newChild.Name)
		if not gun then
			warn(warnPrefix .. "Could not find a gun model with the name: '" .. newChild.Name .. "'!")
			return
		end
		gun = gun:Clone()

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

		-- Add sight parts
		for _, part in ipairs(gun:GetChildren()) do
			if part.Name == "SightReticle" then
				table.insert(sights, part)
			end
		end

		gun.Parent = rig.Weapon
		gunModel = gun
		weldMod.BlankM6D(rig.AnimBase, gun.Grip)

		if firstPerson then
			RefreshViewmodel()
		end

		BindGunInputs()

		ToggleSprint(character:GetAttribute("HoldingSprint"))
		EquipAnim()
		IdleAnim()

		gunAmmo = newChild:WaitForChild("Ammo")

		if not equipped.BoltReady.Value then
			MoveBolt(wepStats.boltDist, true)
		end

		if config.lockFirstPerson then
			player.CameraMode = Enum.CameraMode.LockFirstPerson
		end

		curFireMode = equipped.FireMode.Value

		if gunModel.Grip:FindFirstChild("Laser") then
			laserBeamFP.Attachment0 = gunModel.Grip.Laser
		end

		-- Preload animations
		if wepStats.magType == 1 then
			PlayAnimation(
				wepStats.reloadAnim,
				{ speed = wepStats.reloadSpeedModifier, priority = Enum.AnimationPriority.Action2, transSpeed = 0.17 },
				"Reload",
				true
			)
		else
			PlayAnimation(wepStats.reloadAnim, {
				speed = wepStats.reloadSpeedModifier,
				priority = Enum.AnimationPriority.Action2,
				transSpeed = 0,
				looped = gunAmmo.MagAmmo.MaxValue > 1,
			}, "Reload", true)
			if wepStats.magType == 3 then
				PlayAnimation(wepStats.clipReloadAnim, {
					speed = wepStats.reloadSpeedModifier,
					priority = Enum.AnimationPriority.Action2,
					transSpeed = 0.17,
					looped = false,
				}, "Reload", true)
			end
		end

		local newEquipAnim: AnimationTrack = PlayAnimation(
			wepStats.equipAnim,
			{ priority = Enum.AnimationPriority.Action2, looped = false },
			"Equip",
			true
		)
		newEquipAnim.Stopped:Connect(function()
			equipping = false
		end)

		PlayAnimation(
			wepStats.boltChamber,
			{ priority = Enum.AnimationPriority.Action2, transSpeed = 0.05, looped = false },
			"Chamber",
			true
		)

		if wepStats.operationType == 2 or wepStats.operationType == 3 then
			PlayAnimation(
				wepStats.boltOpen,
				{ priority = Enum.AnimationPriority.Action2, transSpeed = 0, looped = false },
				"BoltOpen",
				true
			)
			PlayAnimation(
				wepStats.boltClose,
				{ priority = Enum.AnimationPriority.Action2, looped = false },
				"BoltClose",
				true
			)
		end

		-- Preload aiming animation if this gun has a setting for it
		if wepStats.aimAnim then
			local aimAnim: AnimationTrack = PlayAnimation(
				wepStats.aimAnim,
				{ looped = true, priority = Enum.AnimationPriority.Action, transSpeed = wepStats.aimTime / 6 },
				"AimAnim",
				true
			)
		end
	elseif newChild.Name == "WeaponRig" then
		weaponRig = newChild
		characterAnimator = weaponRig:WaitForChild("AnimationController", 20).Animator
	end
end)

-- Unequip function
character.ChildRemoved:Connect(function(oldChild)
	if equipped and oldChild:FindFirstChild("SPH_Weapon") and assets.WeaponModels:FindFirstChild(oldChild.Name) then
		Unequip(oldChild)
	end
end)

runService.Heartbeat:Connect(function(dt: number)
	-- Mouse click code
	if equipped and not dead and holdingM1 and cycled and not sprinting and not reloading then
		-- Can the player fire this gun?
		if
			canFire
			and not blocked
			and holdStance == 0
			and IsLoaded()
			and curFireMode > 0
			and (config.fireWithFreelook or (not config.fireWithFreelook and not freeLook))
			and not equipping
		then
			if proneMoveAnim and proneMoveAnim.IsPlaying then
				return
			end
			if not firstPerson and not config.thirdPersonFiring then
				return
			end
			-- Fire gun

			if wepStats.fireAnim then
				PlayAnimation(wepStats.fireAnim, { priority = Enum.AnimationPriority.Action2, looped = false })
			end

			bulletsCurrentlyFired += 1
			ejected = false

			if
				curFireMode == fireModes.Semi
				or curFireMode == fireModes.Manual
				or (curFireMode == fireModes.Burst and bulletsCurrentlyFired >= wepStats.burstNumber)
			then
				canFire = false
				holdingM1 = false
			end
			cycled = false
			local curModel = weaponRig.Weapon:FindFirstChildWhichIsA("Model")
			curModel = gunModel

			-- Camera recoil
			local recoilStats = wepStats.recoil
			local vertRecoil = recoilStats.vertical
			local horzRecoil = recoilStats.horizontal
			horzRecoil *= 100 -- Allows decimals when calculating a random number.
			if aiming then
				vertRecoil /= recoilStats.aimReduction
				horzRecoil /= recoilStats.aimReduction
			end
			if character:GetAttribute("Stance") == "Prone" then
				vertRecoil /= 3
				horzRecoil /= 3
			end
			if equipped:GetAttribute("BipodEnabled") then
				local recoilReduction = wepStats.recoilReduction or 3
				vertRecoil /= recoilReduction
				horzRecoil /= recoilReduction
			end
			horzRecoil = math.random(-horzRecoil, horzRecoil)
			horzRecoil /= 100

			recoilSpring:shove(Vector3.new(vertRecoil, horzRecoil, recoilStats.camShake))

			-- Gun recoil
			recoilStats = wepStats.gunRecoil
			vertRecoil = recoilStats.vertical

			horzRecoil = recoilStats.horizontal
			horzRecoil *= 100
			horzRecoil = math.random(-horzRecoil, horzRecoil)

			if character:GetAttribute("Stance") == "Prone" then
				vertRecoil /= 1.5
				horzRecoil /= 1.5
			end
			if equipped:GetAttribute("BipodEnabled") then
				local recoilReduction = wepStats.recoilReduction or 3
				vertRecoil /= recoilReduction
				horzRecoil /= recoilReduction
			end

			horzRecoil /= 100

			gunRecoilSpring:shove(Vector3.new(vertRecoil, horzRecoil, recoilStats.punchMultiplier))

			-- Shell ejection
			if curFireMode ~= fireModes.Manual then
				EjectShell()
			end

			-- Bullet visibility
			local bulletHolderPart = wepStats.bulletHolder and gunModel:FindFirstChild(wepStats.bulletHolder)
			if bulletHolderPart then
				local bulletNumber = gunAmmo.MagAmmo.MaxValue - (gunAmmo.MagAmmo.Value - 1)
				UpdateBulletTransparency(bulletHolderPart, bulletNumber, 1)
			end

			local tempGunModel = gunModel
			if not firstPerson then
				tempGunModel = weaponRig.Weapon:FindFirstChildWhichIsA("Model")
			end
			bulletHandler.FireFX(player, tempGunModel, "Muzzle", wepStats.muzzleChance)

			-- Move bolt
			--if gunModel:FindFirstChild("Bolt") then
			MoveBolt(wepStats.boltDist)
			--end

			-- Fire bullet
			local shotCount = (wepStats.shotgun and wepStats.shotgunPellets) or 1
			repeat
				shotCount -= 1
				local bulletOrigin, bulletDirection
				local tempSpread = wepStats.spread * 100
				local spreadCFrame = CFrame.Angles(
					math.rad(math.random(-tempSpread, tempSpread) / 100),
					math.rad(math.random(-tempSpread, tempSpread) / 100),
					0
				)
				if firstPerson then
					bulletOrigin = curModel.Grip.Muzzle.WorldCFrame.Position
					bulletDirection = (curModel.Grip.Muzzle.WorldCFrame * spreadCFrame).LookVector
				else
					local muzzle = weaponRig.Weapon:FindFirstChildWhichIsA("Model").Grip.Muzzle
					local muzzlePosition = muzzle.WorldCFrame.Position
					local muzzleDirection = muzzle.WorldCFrame.LookVector

					local rayOrigin = muzzlePosition + (muzzleDirection * -3)
					local rayResult = workspace:Raycast(rayOrigin, muzzleDirection * 3, rayParams)
					if rayResult then
						bulletOrigin = rayResult.Position + muzzleDirection * -0.1
					else
						bulletOrigin = muzzle.WorldCFrame.Position
					end

					bulletDirection = (muzzle.WorldCFrame * spreadCFrame).LookVector
				end

				local bulletVelocity = (bulletDirection * wepStats.muzzleVelocity * config.meterMultiplier) -- 1 Meter = ~3.5 Studs (According to the dev forum)

				local tracerColor = nil
				--print(gunAmmo.MagAmmo.Value % wepStats.tracerTiming)
				if wepStats.tracers and gunAmmo.MagAmmo.Value % wepStats.tracerTiming == 0 then
					tracerColor = wepStats.tracerColor
				end

				bulletHandler.FireBullet(
					weaponRig,
					bulletOrigin,
					bulletDirection,
					bulletVelocity,
					equipped,
					player,
					tracerColor
				)
			until shotCount <= 0

			playerFire:Fire(curModel.Grip.Muzzle.WorldCFrame)

			local cycleTime = wepStats.fireRate
			if curFireMode == fireModes.Burst and wepStats.burstFireRate then
				cycleTime = wepStats.burstFireRate
			end

			if gunModel and wepStats.projectile ~= "Bullet" and gunModel:FindFirstChild(wepStats.projectile) then
				local projectile = gunModel:FindFirstChild(wepStats.projectile)
				projectile.LocalTransparencyModifier = 1
				for _, child in ipairs(projectile:GetDescendants()) do
					if child:IsA("BasePart") then
						child.LocalTransparencyModifier = 1
					end
				end
			end

			task.wait(60 / cycleTime)

			if not equipped then
				return
			end

			if wepStats.autoChamber and curFireMode == fireModes.Manual and not reloading then
				ChamberAnim()
			end

			cycled = true
		elseif not IsLoaded() then
			if curFireMode == fireModes.Manual and gunAmmo.MagAmmo.Value > 0 and not reloading and not chambering then -- Click chamber
				ChamberAnim()
				holdingM1 = false
			elseif
				wepStats.emptyCloseBolt
				and not equipped.Chambered.Value
				and not equipped.BoltReady.Value
				and bulletsCurrentlyFired == 0
			then
				holdingM1 = false
				repChamber:Fire()
				PlayRepSound("SlideRelease")
				MoveBolt(CFrame.new())
			end
		end
	end
end)

runService.RenderStepped:Connect(function(dt: number)
	if math.ceil(1 / dt) < 5 then -- Skip the render stepped function if FPS is lower than 5 to avoid stuttering issues
		print(warnPrefix .. "RenderStepped skipped due to low framerate.")
		return
	end

	moving = humanoid.MoveDirection.Magnitude > 0

	if
		proneMoveAnim
		and character:GetAttribute("Stance") == "Prone"
		and equipped
		and humanoid.FloorMaterial ~= Enum.Material.Air
	then
		if moving and not proneMoveAnim.IsPlaying then
			PlayAnimation(wepStats.proneMoveAnim, { transSpeed = 0.5 })
		elseif not moving and proneMoveAnim.IsPlaying then
			StopAnimation(wepStats.proneMoveAnim, 0.5)
		end
	elseif proneMoveAnim and proneMoveAnim.IsPlaying then
		StopAnimation(wepStats.proneMoveAnim, 0.5)
	end

	headRotationEventCooldown -= dt

	-- Limit camera rotation
	if (humanoid.Sit and not vehicleSeated and firstPerson or freeLook) and config.cameraLimitInSeats then
		local cameraCFrame = humanoidRootPart.CFrame:ToObjectSpace(camera.CFrame)
		local x, y, z = cameraCFrame:ToOrientation()
		local a = camera.CFrame.Position.X
		local b = camera.CFrame.Position.Y
		local c = camera.CFrame.Position.Z

		local xlimit = math.rad(math.clamp(math.deg(x), -60, 60))
		local ylimit = math.rad(math.clamp(math.deg(y), -60, 60))
		local zlimit = math.rad(math.clamp(math.deg(z), -60, 60))
		local limitedCFrame =
			humanoidRootPart.CFrame:ToWorldSpace(CFrame.new(a, b, c) * CFrame.fromOrientation(xlimit, ylimit, zlimit))
		camera.CFrame = CFrame.new(camera.CFrame.Position) * (limitedCFrame - limitedCFrame.Position)
	end

	if not dead and character:FindFirstChild("Head") then
		if not dead then
			local torsoDirection
			if humanoid.RigType == Enum.HumanoidRigType.R6 then
				torsoDirection = character.Torso.CFrame.LookVector
			else
				torsoDirection = character.UpperTorso.CFrame.LookVector
			end

			local lookDirection = camera.CFrame
			if (not config.headRotation or sprinting) and not firstPerson then
				lookDirection = humanoidRootPart.CFrame
			end

			local cameraDirection = humanoidRootPart.CFrame:ToObjectSpace(lookDirection).LookVector
			local rotationCFrame = CFrame.Angles(0, math.asin(cameraDirection.X) / 1.15, 0)
				* CFrame.Angles(-math.asin(lookDirection.LookVector.Y) + math.asin(torsoDirection.Y), 0, 0)
			local neckCFrame = CFrame.new(0, -0.5, 0) * rotationCFrame * CFrame.Angles(-math.rad(90), 0, math.rad(180))
			neckJoint.C1 = neckJoint.C1:Lerp(neckCFrame, 1 - math.exp(-config.headRotationSpeed * dt))
			--neckJoint.C1 = neckCFrame

			if headRotationEventCooldown <= 0 and not dead and not config.disableHeadRotation then
				headRotationEventCooldown = config.headRotationEventRate
				bodyAnimRequest:Fire(neckJoint.C1)
			end
		end

		-- Check if player is in first person
		if not firstPerson and character.Head.LocalTransparencyModifier >= fpThreshold then
			firstPerson = true
			if equipped then
				BindAiming()
				if flashlightEnabled then
					if gunModel.Grip:FindFirstChild("Flashlight") then
						gunModel.Grip.Flashlight:FindFirstChildWhichIsA("Light").Enabled = true
						weaponRig.Weapon
							:FindFirstChildWhichIsA("Model").Grip.Flashlight
							:FindFirstChildWhichIsA("Light").Enabled =
							false
					end
				end
				if laserEnabled and config.laserTrail then
					laserBeamTP.Enabled = false
					laserBeamFP.Enabled = true
				end
			end
		elseif firstPerson and character.Head.LocalTransparencyModifier <= fpThreshold then
			firstPerson = false
			UnbindAiming()
			if equipped then
				if laserEnabled and config.laserTrail then
					laserBeamTP.Enabled = true
					laserBeamFP.Enabled = false
					if not laserBeamTP.Attachment0 then
						laserBeamTP.Attachment0 = GetThirdPersonGunModel().Grip.Laser
					end
				end
				if gunModel.Grip:FindFirstChild("Flashlight") then
					gunModel.Grip.Flashlight:FindFirstChildWhichIsA("Light").Enabled = false
					if weaponRig.Weapon:FindFirstChildWhichIsA("Model") and flashlightEnabled then
						weaponRig.Weapon
							:FindFirstChildWhichIsA("Model").Grip.Flashlight
							:FindFirstChildWhichIsA("Light").Enabled =
							true
					end
				end
			end
			ResetHead()
			cameraOffsetTarget = Vector3.zero
		end

		-- First person body offset
		if config.firstPersonBody and firstPerson then
			local xHead = character.HumanoidRootPart.CFrame:ToObjectSpace(camera.CFrame):ToEulerAngles()
			local rotationOffset = -1.2 + (xHead + 1.4) / 2.8
			cameraOffsetTarget = Vector3.new(0, 0, rotationOffset)
		else
			cameraOffsetTarget = Vector3.zero
		end

		local xOffset = 0
		local yOffset = 0
		local zOffset = cameraOffsetTarget.Z

		if character:GetAttribute("Stance") == "Crouched" then
			yOffset = -1
			if firstPerson then
				zOffset -= 0.3
			end
		elseif character:GetAttribute("Stance") == "Prone" then
			yOffset = -1.5
			if firstPerson then
				zOffset = -1.7
			end
		end

		-- Lean offset
		local lean = character:GetAttribute("LeanDirection") or 0
		if lean < 0 then
			xOffset = -1
			yOffset += -0.2
		elseif lean > 0 then
			xOffset = 1
			yOffset += -0.2
		end

		if not vehicleSeated and camera.CameraType == Enum.CameraType.Custom then
			-- Update camera offset
			cameraOffsetTarget = Vector3.new(xOffset, yOffset, zOffset)
			humanoid.CameraOffset = humanoid.CameraOffset:Lerp(cameraOffsetTarget, 0.1 * dt * 60)

			-- Update leaning offset
			rootJoint.C1 = rootJoint.C1:Lerp(
				CFrame.new(-xOffset / 2, 0, 0) * CFrame.Angles(math.rad(90), math.rad(180) + math.rad(17 * lean), 0),
				0.1 * dt * 60
			)
			cameraLeanRotation = LerpNumber(cameraLeanRotation, 15 * -lean, 0.1)
			camera.CFrame *= CFrame.Angles(0, 0, math.rad(cameraLeanRotation))

			-- Camera tilt
			if config.cameraTilting and firstPerson then
				local maxTiltAngle = 2
				local relativeVelocity = humanoidRootPart.CFrame:VectorToObjectSpace(humanoidRootPart.Velocity)
				local mouseDelta = userInputService:GetMouseDelta()
				local targetCameraRollAngle = math.clamp(-relativeVelocity.X, -maxTiltAngle, maxTiltAngle)
					+ mouseDelta.X / 2
				cameraRollAngle = LerpNumber(cameraRollAngle, targetCameraRollAngle, 0.07 * dt * 60)
				camera.CFrame *= CFrame.Angles(0, 0, math.rad(cameraRollAngle))
			end
		end

		-- Update viewmodel
		if equipped and camera.CameraType == Enum.CameraType.Custom then
			if firstPerson and not viewmodelVisible then
				-- Player switched to first person
				RefreshViewmodel()
				ToggleSprint(character:GetAttribute("HoldingSprint"))
			end

			-- Update recoil and movement springs
			UpdateViewmodelPosition(dt)
		elseif viewmodelVisible and not equipping then
			viewmodelVisible = false
		end

		-- Update movement sway
		local walkSpeed = math.floor(humanoid.WalkSpeed)
		local tempDampening = config.bobDampening
		local difference = tempDampening - (tempDampening / (walkSpeed / config.walkSpeed))
		difference /= 2
		tempDampening -= difference
		if aiming then
			tempDampening *= config.aimBobDampening
		end

		local tempBobSpeed = config.bobSpeed
		tempBobSpeed *= walkSpeed / config.walkSpeed

		if not humanoid.Sit and moving and humanoid.FloorMaterial ~= Enum.Material.Air then
			local moveSway = Vector3.new(
				GetSineOffset(tempBobSpeed),
				GetSineOffset(tempBobSpeed / 2),
				GetSineOffset(tempBobSpeed / 2)
			)
			moveSpring:shove(moveSway / tempDampening * humanoidRootPart.Velocity.Magnitude / tempDampening * dt * 60)
		end

		local updatedMoveSway = moveSpring:update(dt)
		animBase.CFrame = animBase.CFrame:ToWorldSpace(
			CFrame.new(updatedMoveSway.Y, updatedMoveSway.X, 0)
				* CFrame.Angles(updatedMoveSway.Y * 0.3, 0, updatedMoveSway.Y * 0.8)
		)

		-- Laser raycast
		if equipped and laserEnabled then
			if not laserDotUI.Enabled then
				laserDotUI.Enabled = true
				laserDotUI.Dot.ImageColor3 = gunModel.Grip.Laser.Color.Value

				if config.laserTrail then
					laserBeamFP.Color = ColorSequence.new(gunModel.Grip.Laser.Color.Value)
					laserBeamTP.Color = ColorSequence.new(gunModel.Grip.Laser.Color.Value)

					if firstPerson then
						laserBeamFP.Enabled = true
					else
						laserBeamTP.Enabled = true
						if not laserBeamTP.Attachment0 then
							laserBeamTP.Attachment0 = GetThirdPersonGunModel().Grip.Laser
						end
					end
				end
			end
			local laserPoint: Attachment = firstPerson and gunModel.Grip.Laser or GetThirdPersonGunModel().Grip.Laser
			local laserRayParams = RaycastParams.new()
			laserRayParams.FilterType = Enum.RaycastFilterType.Exclude
			laserRayParams.FilterDescendantsInstances = { gunModel, character }
			laserRayParams.RespectCanCollide = true
			local rayResult =
				workspace:Raycast(laserPoint.WorldPosition, laserPoint.WorldCFrame.LookVector * 600, laserRayParams)
			if rayResult then
				laserDotPoint.WorldPosition = rayResult.Position
			else
				laserDotPoint.WorldPosition = laserPoint.WorldPosition + laserPoint.WorldCFrame.LookVector.Unit * 600
			end
		elseif laserDotUI.Enabled then
			laserDotUI.Enabled = false
			laserBeamFP.Enabled = false
			laserBeamTP.Enabled = false
		end

		-- Camera movement sway
		if
			config.cameraMovement
			and (firstPerson and not humanoid.Sit)
			and not vehicleSeated
			and camera.CameraType == Enum.CameraType.Custom
		then
			camera.CFrame *= CFrame.Angles(
				math.rad(updatedMoveSway.X / config.cameraBobDampening),
				math.rad(updatedMoveSway.Y / config.cameraBobDampening),
				0
			)
		end

		-- Update sights
		for _, sight: BasePart in ipairs(sights) do
			local frame = sight.SurfaceGui.Frame
			local sightUI = frame:FindFirstChild("Reticle") or frame:FindFirstChild("Holo")

			local dist = sight.CFrame:PointToObjectSpace(camera.CFrame.Position) / sight.Size
			sightUI.Position = UDim2.fromScale(0.5 + dist.X, 0.5 - dist.Y)

			if sightUI.Name == "Holo" then
				local newSize = camera.FieldOfView / 70
				sightUI.Size = UDim2.fromScale(newSize, newSize)
			end
		end

		if aiming then
			camera.FieldOfView = LerpNumber(camera.FieldOfView, aimFOVTarget, 0.3)
		end
	end

	-- Prone angle
	if character:GetAttribute("Stance") == "Prone" and config.proneAngle then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		params.IgnoreWater = true
		params.RespectCanCollide = true

		local rayResult = workspace:Raycast(humanoidRootPart.Position, Vector3.new(0, -2, 0), params)
		if rayResult and rayResult.Instance then
			--print(rayResult.Normal.X)
			--rootJoint.C0 *= CFrame.Angles(rayResult.Normal.X, 0, 0)
			--rootJoint.C0 *= CFrame.Angles(rayResult.Normal.X, rayResult.Normal.Y, rayResult.Normal.Z)
			--print(rootJoint.C0, rootJoint.C1, rayResult.Normal)

			local rotateToFloorCFrame =
				GetRotationBetween(humanoidRootPart.CFrame.UpVector, rayResult.Normal, Vector3.new(1, 0, 0))
			rootJoint.C0 *= CFrame.Angles(rotateToFloorCFrame.X, rotateToFloorCFrame.Y, rotateToFloorCFrame.Z)
			--print(rotateToFloorCFrame.UpVector)
			local goalCF = rotateToFloorCFrame * humanoidRootPart.CFrame
			--wedge.CFrame = wedge.CFrame:Lerp(goalCF, 5 * dt).Rotation + wedge.CFrame.Position
		end
	end
end)

userInputService.InputChanged:Connect(function(input)
	if aiming and input.UserInputType == Enum.UserInputType.MouseWheel then
		if userInputService:IsKeyDown(config.holdForScrollZoom) then
			-- Zoom
			local newFOV = aimFOVTarget - input.Position.Z * 3
			aimFOVTarget = math.clamp(newFOV, wepStats.aimFovMin, wepStats.aimFovMax or defaultFOV)
		else
			-- Sensitivity
			aimSensitivity = math.clamp(aimSensitivity - 0.01 * -input.Position.Z, 0.005, 1)
			userInputService.MouseDeltaSensitivity = aimSensitivity
			player:SetAttribute("SavedAimSensitivity", aimSensitivity)
		end
	end
end)

-- Keep track of if this character is in a vehicle seat and unequip tools if they are.
humanoid.Seated:Connect(function(seated, seatPart)
	if seated then -- In a seat
		if seatPart:IsA("VehicleSeat") and not config.canEquipInVehicleSeat then
			vehicleSeated = true
			if equipped then
				humanoid:UnequipTools()
			end
		else
			vehicleSeated = false
		end
	else -- Exiting a seat
		vehicleSeated = false
	end
end)

local canJump = true
character:SetAttribute("ClientCanJump", canJump)

userInputService.JumpRequest:Connect(function()
	if humanoid.Sit then
		character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	elseif character:GetAttribute("Stance") == "Standing" then
		if character.Humanoid.FloorMaterial == Enum.Material.Air then
			return
		end
		if canJump then
			canJump = false
			character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			task.wait(config.jumpCooldown)
			canJump = true
		else
			character.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		end
	else
		character.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end

	character:SetAttribute("ClientCanJump", canJump)
end)

-- Toggle viewmodel sprinting effects if player is sprinting.
character:GetAttributeChangedSignal("Sprinting"):Connect(function()
	sprinting = character:GetAttribute("Sprinting")
	if sprinting and equipped then
		ToggleSprint(true)
	else
		ToggleSprint(false)
	end
end)

toggleViewmodelSprint.Event:Connect(function(toggle)
	--print(toggle)
	ToggleSprint(toggle)
	sprinting = toggle
	if not toggle then
		aimHeld = false
	end
end)

for _, part in collectionService:GetTagged("SPH_NoCollide") do
	if part:IsA("BasePart") then
		table.insert(rayParams.FilterDescendantsInstances, part)
	end
end

collectionService:GetInstanceAddedSignal("SPH_NoCollide"):Connect(function(newInstance)
	if newInstance:IsA("BasePart") then
		table.insert(rayParams.FilterDescendantsInstances, newInstance)
	end
end)

local lastAirborne = 0
character:GetAttributeChangedSignal("Airborne"):Connect(function()
	local newValue = character:GetAttribute("Airborne")
	local airTime = tick() - lastAirborne
	if not newValue and airborne and airTime >= 0.5 then
		swaySpring:shove(Vector3.new(0, -0.7, 0))
		assets.Events.PlayCharacterSound:FireServer("Landing")
	elseif newValue and not airborne then
		swaySpring:shove(Vector3.new(0, 0.4, 0))
	end

	airborne = newValue
	if airborne then
		lastAirborne = tick()
	end
end)
