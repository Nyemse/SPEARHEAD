-- This script makes body parts and equipment visible in first person
local config = require(game:GetService("ReplicatedStorage").SPH_Assets.GameConfig)
local dead = false
local vehicleSeated

if config.firstPersonBody then
	local Character = script.Parent.Parent
	local RunService = game:GetService("RunService")
	local gunEquipped

	local humanoid = Character:WaitForChild("Humanoid")
	local torso
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		torso = Character:WaitForChild("Torso")
	else
		torso = Character:WaitForChild("UpperTorso")
	end

	local shoulder = torso:WaitForChild("Left Shoulder")

	humanoid.Died:Connect(function()
		dead = true
	end)

	local function CheckForBodyPartNames(model)
		for _, part in ipairs(model:GetChildren()) do
			local checkPart = Character:FindFirstChild(part.Name)
			if checkPart and checkPart:IsA("BasePart") then
				if not (string.find(checkPart.Name, "Arm") and gunEquipped) then
					return part
				end
			end
		end
	end

	local tempOverride

	Character.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("Tool") and child:FindFirstChild("SPH_Weapon") then
			tempOverride = true
			task.wait(0.1)
			tempOverride = false
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		if
			not Character:FindFirstChild("Torso") and not Character:FindFirstChild("UpperTorso")
			or dead
			or vehicleSeated
		then
			return
		elseif Character:FindFirstChild("Head") and Character.Head.LocalTransparencyModifier == 0 then
			return
		end

		-- Check if gun is equipped
		gunEquipped = Character:FindFirstChildWhichIsA("Tool")
		if gunEquipped and not gunEquipped:FindFirstChild("SPH_Weapon") then
			gunEquipped = nil
		end

		--local armsEnabled = torso["Left Shoulder"].Enabled
		local armsEnabled = not gunEquipped and not tempOverride

		-- Loop through character children
		for _, obj in ipairs(Character:GetChildren()) do
			-- obj is a part
			if obj:IsA("BasePart") then
				-- Make visible if part is a leg, the torso, or arms when a gun isn't equipped
				if
					(string.find(obj.Name, "Arm") and armsEnabled)
					or string.find(obj.Name, "Leg")
					or string.find(obj.Name, "Torso")
					or string.find(obj.Name, "Foot")
				then
					obj.LocalTransparencyModifier = 0
				end

				-- obj is a model with parts inside
			elseif obj:IsA("Model") and obj:FindFirstChildWhichIsA("BasePart") then
				-- Conventional morph
				local middlePart = obj:FindFirstChild("Middle")
					or obj:FindFirstChild("Grip")
					or CheckForBodyPartNames(obj)
				if middlePart and obj.Name ~= "WeaponRig" then
					if string.find(obj.Name, "Holster_") and not config.firstPersonHolsters then
						continue
					end
					-- Check morph welds
					local welds = middlePart:GetJoints()
					local badMorph = false
					for _, cWeld in ipairs(welds) do
						if cWeld.Part0 == Character.Head or cWeld.Part1 == Character.Head then
							badMorph = true
							break
						elseif
							(string.find(cWeld.Part0.Name, "Arm") or string.find(cWeld.Part1.Name, "Arm"))
							and gunEquipped
						then
							badMorph = true
							break
						end
					end

					if badMorph then
						continue
					end
					-- Loop through model
					for _, part in ipairs(obj:GetDescendants()) do
						if part:IsA("BasePart") or part:IsA("Texture") or part:IsA("Decal") then
							part.LocalTransparencyModifier = 0
						end
					end

					-- Non conventional morphs that only include one part
				elseif #obj:GetChildren() == 1 then
					local part = obj:FindFirstChildWhichIsA("BasePart")
					local welds = part:GetJoints()
					local headMorph = false
					for _, cWeld in ipairs(welds) do
						-- If welded to the head, ignore
						if cWeld.Part0 == Character.Head or cWeld.Part1 == Character.Head then
							headMorph = true
							break
						end
					end

					if not headMorph then
						part.LocalTransparencyModifier = 0
						for _, child in ipairs(part:GetChildren()) do
							if child:IsA("Texture") or child:IsA("Decal") then
								child.LocalTransparencyModifier = 0
							end
						end
					end
				elseif obj:GetAttribute("FirstPersonVisible") then
					for _, childPart in obj:GetChildren() do
						if childPart:IsA("BasePart") then
							childPart.LocalTransparencyModifier = 0
						end
					end
				end
			elseif obj:IsA("Accessory") and config.showAccessoriesFP then
				local part = obj:FindFirstChildWhichIsA("BasePart")
				if part then
					local attachedPart = part.AccessoryWeld.Part1
					part.LocalTransparencyModifier = attachedPart.Name == "Head" and 1 or 0
				end
			end
		end
	end)

	humanoid.Seated:Connect(function(seated, seatPart)
		if seated and seatPart:IsA("VehicleSeat") then
			vehicleSeated = true
		else
			vehicleSeated = false
		end
	end)
end
