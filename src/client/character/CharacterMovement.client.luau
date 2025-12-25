-- Movement leaning
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local contextActionService = game:GetService("ContextActionService")
local tweenService = game:GetService("TweenService")

local localPlayer: Player = players.LocalPlayer
local playerCharacter: Model = localPlayer.Character or localPlayer.CharacterAdded:Wait()
local humanoid: Humanoid = playerCharacter:WaitForChild("Humanoid", 20)
local rootPart: BasePart = playerCharacter:WaitForChild("HumanoidRootPart", 20)
local rootJoint: BasePart = rootPart:WaitForChild("RootJoint", 20)
local assets = replicatedStorage.SPH_Assets
local modules = assets.Modules
local toggleViewmodelSprint = assets.Events.ToggleViewmodelSprint

local bridgeNet = require(modules.BridgeNet)
local playerLean = bridgeNet.CreateBridge("PlayerLean")

local config = require(replicatedStorage.SPH_Assets.GameConfig)
local c0Ref = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0)

local maxTiltAngle = config.maxLeanAngle
local movementVector = Vector3.zero

local canChangeWalkSpeed = script:GetAttribute("CanChangeWalkSpeed")
local strafing = false
local strafingMult = config.strafeSpeedMultiplier
local airborne = false

local canChangeStance = true

local stance = 0
local crouchIdleAnim: AnimationTrack = humanoid.Animator:LoadAnimation(assets.Animations.Crouch_Idle)
crouchIdleAnim.Looped = true
crouchIdleAnim.Priority = config.useHigherAnimPriority and Enum.AnimationPriority.Action or Enum.AnimationPriority.Idle

local crouchMoveAnim: AnimationTrack = humanoid.Animator:LoadAnimation(assets.Animations.Crouch_Move)
crouchMoveAnim.Looped = true
crouchMoveAnim.Priority = config.useHigherAnimPriority and Enum.AnimationPriority.Action2
	or Enum.AnimationPriority.Movement

local proneIdleAnim: AnimationTrack = humanoid.Animator:LoadAnimation(assets.Animations.Prone_Idle)
proneIdleAnim.Looped = true
proneIdleAnim.Priority = config.useHigherAnimPriority and Enum.AnimationPriority.Action or Enum.AnimationPriority.Idle

local proneMoveAnim: AnimationTrack = humanoid.Animator:LoadAnimation(assets.Animations.Prone_Move)
proneMoveAnim.Looped = true
proneMoveAnim.Priority = config.useHigherAnimPriority and Enum.AnimationPriority.Action2
	or Enum.AnimationPriority.Movement

local moveAnim -- Temporary variable only used to store which movement animation is being used.

local walkAnim
local sprintAnim

local moving = false

script:SetAttribute("WalkSpeed", config.walkSpeed)
script:SetAttribute("SprintSpeed", config.sprintSpeed)
script:SetAttribute("CrouchSpeed", config.crouchSpeed)
script:SetAttribute("ProneSpeed", config.proneSpeed)

playerCharacter:SetAttribute("Stance", "Standing")
playerCharacter:SetAttribute("LeanDirection", 0)

local function LerpNumber(number: number, target: number, speed: number)
	return number + (target - number) * speed
end

local function ToggleSprint(toggle: boolean)
	toggleViewmodelSprint:Fire(toggle)
end

local function UpdateCharacterTilt(character, deltaTime)
	if not humanoid or humanoid.Health <= 0 or not rootPart or not rootJoint then
		return
	end
	local MoveDirection = rootPart.CFrame:VectorToObjectSpace(humanoid.MoveDirection)

	local tilt = c0Ref:Inverse() * rootJoint.C0

	local target =
		CFrame.Angles(math.rad(-MoveDirection.Z) * maxTiltAngle, math.rad(-MoveDirection.X) * maxTiltAngle, 0)

	if
		humanoid.Sit
		or humanoid.Health <= 0
		or script:GetAttribute("DisableLean")
		or character:GetAttribute("SeatAnim")
	then
		target = CFrame.new()
	end

	tilt = tilt:Lerp(target, 0.2 ^ (1 / (deltaTime * 60)))
	rootJoint.C0 = c0Ref * tilt
end

local function IsCharacterStrafing(character)
	if not character:FindFirstChild("HumanoidRootPart") then
		return
	end
	if movementVector.Magnitude > 0 then
		local characterLookVector = character.HumanoidRootPart.CFrame.LookVector
		local dotProduct = movementVector:Dot(characterLookVector)
		return (dotProduct < 0.7)
	end
end

local function PlayCharSound(soundName)
	assets.Events.PlayCharacterSound:FireServer(soundName)
end

local function ChangeLean(newLean)
	local lean = playerCharacter:GetAttribute("LeanDirection")
	if not config.canLean then
		return
	end -- Return if the player can't lean
	if newLean ~= lean then
		PlayCharSound("Lean")
	end
	lean = newLean
	playerCharacter:SetAttribute("LeanDirection", lean)
	playerLean:Fire(newLean)
end

local function ChangeStance(change, override)
	if canChangeStance or override then
		canChangeStance = false
		task.delay(config.stanceChangeTime * 0.7, function()
			canChangeStance = true
		end)

		local number = stance + change

		-- Correct number if it's too low or too high
		if number < 0 then
			number = 0
		elseif number > 2 then
			number = 2
		end

		local preMove = false
		if moveAnim then
			preMove = moveAnim.IsPlaying
		end

		if number == 0 then -- Walking
			script.Parent.CharacterMovement:SetAttribute("DisableLean", false)
			if moveAnim then
				moveAnim:Stop(config.stanceChangeTime)
			end
			moveAnim = nil
			crouchIdleAnim:Stop(config.stanceChangeTime)
			playerCharacter:SetAttribute("Stance", "Standing")
			tweenService:Create(humanoid, TweenInfo.new(config.stanceChangeTime), { HipHeight = 0 }):Play()
			PlayCharSound("Uncrouch")

			if playerCharacter:GetAttribute("HoldingSprint") then
				playerCharacter:SetAttribute("Sprinting", true)
				ToggleSprint(true)
			end
		elseif number == 1 then -- Crouching
			script.Parent.CharacterMovement:SetAttribute("DisableLean", false)
			if moveAnim then
				moveAnim:Stop(config.stanceChangeTime)
			end
			moveAnim = crouchMoveAnim
			if moving then
				moveAnim:Play(config.stanceChangeTime)
			end
			proneIdleAnim:Stop(config.stanceChangeTime)
			crouchIdleAnim:Play(config.stanceChangeTime)
			playerCharacter:SetAttribute("Stance", "Crouched")
			playerCharacter:SetAttribute("Sprinting", false)
			tweenService:Create(humanoid, TweenInfo.new(config.stanceChangeTime), { HipHeight = 0 }):Play()
			if stance == 0 then
				PlayCharSound("Crouch")
			elseif stance == 2 then
				PlayCharSound("Unprone")
			end
		elseif number == 2 then -- Prone
			ChangeLean(0)
			script.Parent.CharacterMovement:SetAttribute("DisableLean", true)
			if moveAnim then
				moveAnim:Stop(config.stanceChangeTime)
			end
			moveAnim = proneMoveAnim
			crouchIdleAnim:Stop(config.stanceChangeTime)
			proneIdleAnim:Play(config.stanceChangeTime)
			playerCharacter:SetAttribute("Stance", "Prone")
			tweenService:Create(humanoid, TweenInfo.new(config.stanceChangeTime * 1.5), { HipHeight = -2 }):Play()
			PlayCharSound("Prone")
		end

		if preMove and moveAnim then
			moveAnim:Play()
		end

		stance = number
	end
end

local function HandleMovementInput(actionName: string, inputState: EnumItem, inputObject: InputObject)
	local inputBegan = Enum.UserInputState.Begin
	local inputEnded = Enum.UserInputState.End
	local lean = playerCharacter:GetAttribute("LeanDirection")
	local sprinting = playerCharacter:GetAttribute("Sprinting")
	local equipped = playerCharacter:FindFirstChildWhichIsA("Tool")
		and playerCharacter:FindFirstChildWhichIsA("Tool"):FindFirstChild("SPH_Weapon")

	if actionName == "SPH_Sprint" then -- Sprint hold
		local sprintHeld = inputState == inputBegan
		playerCharacter:SetAttribute("HoldingSprint", sprintHeld)
		if sprintHeld and stance < 2 and moving then -- Begin sprinting
			playerCharacter:SetAttribute("Sprinting", true)
			if stance == 1 then
				ChangeStance(-1, true)
			end
			if equipped and moving then
				ToggleSprint(true)
			end
			ChangeLean(0)
		elseif stance == 0 then -- End sprinting
			playerCharacter:SetAttribute("Sprinting", false)
			ToggleSprint(false)
		end
	elseif inputState == inputBegan then -- Other inputs
		if actionName == "SPH_StanceLower" and inputState == inputBegan and stance < 2 and not humanoid.Sit then -- Lower stance
			if not config.canCrouch and stance == 0 then
				return
			end -- If the player is standing and unable to crouch then return
			if not config.canProne and stance == 1 then
				return
			end -- If the player is crouched and unable to prone then return
			ChangeStance(1)
			if sprinting then
				ToggleSprint(false)
			end
		elseif actionName == "SPH_StanceRaise" and inputState == inputBegan and stance > 0 then -- Raise stance
			ChangeStance(-1)
		elseif
			actionName == "SPH_LeanLeft"
			and inputState == inputBegan
			and stance < 2
			and not sprinting
			and not humanoid.Sit
		then -- Lean left
			if lean == -1 then
				ChangeLean(0)
			else
				ChangeLean(-1)
			end
		elseif
			actionName == "SPH_LeanRight"
			and inputState == inputBegan
			and stance < 2
			and not sprinting
			and not humanoid.Sit
		then -- Lean right
			if lean == 1 then
				ChangeLean(0)
			else
				ChangeLean(1)
			end
		end
	end
end

local function BindCharacterInputs() -- Bind movement inputs
	contextActionService:BindActionAtPriority(
		"SPH_Sprint",
		HandleMovementInput,
		false,
		config.movementInputPriority,
		unpack(config.keySprint)
	)
	contextActionService:BindActionAtPriority(
		"SPH_StanceLower",
		HandleMovementInput,
		config.mobileButtons,
		config.movementInputPriority,
		unpack(config.lowerStance)
	)
	contextActionService:BindActionAtPriority(
		"SPH_StanceRaise",
		HandleMovementInput,
		config.mobileButtons,
		config.movementInputPriority,
		unpack(config.raiseStance)
	)
	contextActionService:BindActionAtPriority(
		"SPH_LeanLeft",
		HandleMovementInput,
		false,
		config.movementInputPriority,
		unpack(config.leanLeft)
	)
	contextActionService:BindActionAtPriority(
		"SPH_LeanRight",
		HandleMovementInput,
		false,
		config.movementInputPriority,
		unpack(config.leanRight)
	)

	contextActionService:SetTitle("SPH_StanceLower", "Crouch")
	contextActionService:SetPosition("SPH_StanceLower", UDim2.fromScale(0.4, 0))

	contextActionService:SetTitle("SPH_StanceRaise", "Stand")
	contextActionService:SetPosition("SPH_StanceRaise", UDim2.fromScale(0.55, -0.25))
end
BindCharacterInputs()

local function UnbindCharacterInputs() -- Remove movement inputs
	contextActionService:UnbindAction("SPH_Sprint")
	contextActionService:UnbindAction("SPH_StanceLower")
	contextActionService:UnbindAction("SPH_StanceRaise")
	contextActionService:UnbindAction("SPH_LeanLeft")
	contextActionService:UnbindAction("SPH_LeanRight")
end

runService.RenderStepped:Connect(function(deltaTime)
	movementVector = humanoid.MoveDirection.Unit

	if config.movementLeaning then -- Only tilt character if this setting is enabled
		UpdateCharacterTilt(playerCharacter, deltaTime)

		if config.replicateMovementLeaning then -- Tilt other characters if this setting is enabled
			for _, player in ipairs(players:GetPlayers()) do
				if player ~= localPlayer and player.Character then
					UpdateCharacterTilt(player.Character, deltaTime)
				end
			end
		end
	end

	if canChangeWalkSpeed then
		-- Decide what the player's target walk speed should be
		local targetWalkSpeed = script:GetAttribute("WalkSpeed")
		if playerCharacter:GetAttribute("Stance") == "Prone" then
			targetWalkSpeed = script:GetAttribute("ProneSpeed")
		elseif playerCharacter:GetAttribute("Stance") == "Crouched" then
			targetWalkSpeed = script:GetAttribute("CrouchSpeed")
		elseif playerCharacter:GetAttribute("Sprinting") then
			if not strafing or (config.canSprintWhileStrafing and strafing) then
				targetWalkSpeed = script:GetAttribute("SprintSpeed")
			end
		end

		-- Reduce speed if player is low on health
		if humanoid.Health < 25 and config.lowHealthEffects then
			targetWalkSpeed *= humanoid.Health / 25
		end

		-- Reduce speed if player is strafing
		strafing = IsCharacterStrafing(playerCharacter)
		playerCharacter:SetAttribute("Strafing", strafing)
		if strafing then
			targetWalkSpeed *= strafingMult
		end

		-- Smoothly transition to new walk speed
		humanoid.WalkSpeed = LerpNumber(humanoid.WalkSpeed, targetWalkSpeed, 0.2 * deltaTime * 60)
	end

	-- Check if player is moving
	if moveAnim then
		moveAnim:AdjustSpeed(humanoid.WalkSpeed / 6)
	end
	if humanoid.MoveDirection.Magnitude > 0 and not moving then
		moving = true
		if moveAnim then
			moveAnim:Play(config.stanceChangeTime)
		end
	elseif humanoid.MoveDirection.Magnitude <= 0 then
		moving = false
		if playerCharacter:GetAttribute("Sprinting") then
			ToggleSprint(false)
		end
		if moveAnim then
			moveAnim:Stop(config.stanceChangeTime)
		end
	end
end)

humanoid.Seated:Connect(function(seated, seatPart)
	if seated then -- In a seat
		UnbindCharacterInputs()
		ToggleSprint(false)
		ChangeLean(0)
		if playerCharacter:GetAttribute("Stance") == "Crouched" then
			ChangeStance(-1, true)
		elseif playerCharacter:GetAttribute("Stance") == "Prone" then
			ChangeStance(-1, true)
			ChangeStance(-1, true)
		end
	else -- Exiting a seat
		BindCharacterInputs()
	end
end)

-- This allows other scripts to stop this script from changing the player's walk speed.
script:GetAttributeChangedSignal("CanChangeWalkSpeed"):Connect(function()
	canChangeWalkSpeed = script:GetAttribute("CanChangeWalkSpeed")
end)
