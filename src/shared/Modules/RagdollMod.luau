local module = {}

module.MakeCorpse = function(character: Model)
	local humanoid: Humanoid = character.Humanoid
	local humanoidRootPart = character.HumanoidRootPart
	local newGroup = Instance.new("Model")
	newGroup.Parent = workspace
	newGroup.Name = character.Name .. "_Dead"

	-- Create ragdoll
	for _, v in pairs(character:GetDescendants()) do
		if v:IsA("Motor6D") then
			if not v.Part0 or not v.Part1 then
				continue
			elseif v.Part0.Name == "HumanoidRootPart" or v.Part1.Name == "HumanoidRootPart" then
				v.Enabled = false
			elseif v.Part0.Parent == character or v.Part1.Parent == character then
				local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
				a0.CFrame = v.C0
				a1.CFrame = v.C1
				a0.Parent = v.Part0
				a1.Parent = v.Part1

				if humanoid.RigType == Enum.HumanoidRigType.R6 then
					if v.Part1.Name == "Left Leg" then
						a1.Position -= Vector3.new(-0.5, 0, 0)
						a0.Position -= Vector3.new(-0.5, 0, 0)
					elseif v.Part1.Name == "Right Leg" then
						a1.Position -= Vector3.new(0.5, 0, 0)
						a0.Position -= Vector3.new(0.5, 0, 0)
					end
				end

				local b = Instance.new("BallSocketConstraint")
				b.Attachment0 = a0
				b.Attachment1 = a1
				b.Parent = v.Part0
				--b.LimitsEnabled = true

				v:Destroy()
			end
		end
	end

	local shirt = character:FindFirstChildWhichIsA("Shirt")
	if shirt then
		shirt.Parent = newGroup
	end

	local pants = character:FindFirstChildWhichIsA("Pants")
	if pants then
		pants.Parent = newGroup
	end

	for _, v: BasePart in pairs(character:GetChildren()) do
		if v:IsA("Part") then
			v.Parent = newGroup
			v:SetNetworkOwner()
			if v.Name ~= "HumanoidRootPart" then
				local hitBox = Instance.new("Part")
				hitBox.Size = v.Size * 0.5
				hitBox.Transparency = 1
				hitBox.Massless = true
				local weld = Instance.new("Weld")
				weld.Part0 = v
				weld.Part1 = hitBox
				weld.Parent = hitBox
				hitBox.Parent = v
			end
		end
	end

	humanoid.Parent = newGroup
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	local fakeHumanoid = Instance.new("Humanoid")
	fakeHumanoid.MaxHealth = 0
	fakeHumanoid.Parent = character

	for _, v in pairs(character:GetChildren()) do
		if v:IsA("Accoutrement") then
			v.Parent = newGroup
			humanoid:AddAccessory(v:Clone())
			v:Destroy()
		elseif v:IsA("Model") then
			v.Parent = newGroup
		end
	end

	for _, state in ipairs(Enum.HumanoidStateType:GetEnumItems()) do
		if state == Enum.HumanoidStateType.None then
			continue
		else
			humanoid:SetStateEnabled(state, false)
		end
	end

	humanoidRootPart.Anchored = true
	humanoidRootPart.CanCollide = false
	humanoidRootPart.CanQuery = false
	humanoidRootPart.CanTouch = false

	return newGroup
end

return module
