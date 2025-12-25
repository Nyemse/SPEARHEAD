local newRig = workspace.CurrentCamera:WaitForChild("WeaponRig", 20)

local function SetupListeners(rig)
	local lArm = rig["Left Arm"]
	local rArm = rig["Right Arm"]
	local fakelArm = rig.FakeArms["Left Arm"]
	local fakerArm = rig.FakeArms["Right Arm"]
	local fakeShirt = rig.FakeArms["Shirt"]
	local rigShirt = rig:WaitForChild("Clothing")
	fakeShirt.ShirtTemplate = rigShirt.ShirtTemplate

	rigShirt.Changed:Connect(function()
		fakeShirt.ShirtTemplate = rigShirt.ShirtTemplate
	end)

	fakelArm.Color = lArm.Color
	lArm.Changed:Connect(function()
		fakelArm.Color = lArm.Color
	end)

	fakerArm.Color = rArm.Color
	rArm.Changed:Connect(function()
		fakerArm.Color = rArm.Color
	end)

	newRig.Destroying:Connect(function()
		task.wait()
		newRig = workspace.CurrentCamera:WaitForChild("WeaponRig", 20)
		if newRig then
			SetupListeners(newRig)
		end
	end)
end

if newRig and newRig.Parent and newRig:FindFirstChild("FakeArms") then
	SetupListeners(newRig)
end
