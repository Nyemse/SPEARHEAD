local assets = game:GetService("ReplicatedStorage").SPH_Assets
local config = require(assets.GameConfig)
local dead = false

if config.fallDamage then
	local runService = game:GetService("RunService")
	local character = script.Parent.Parent
	local humanoid: Humanoid = character:WaitForChild("Humanoid")
	local humanoidRootPart: BasePart = character:WaitForChild("HumanoidRootPart")
	local prevHeight = humanoidRootPart.Position.Y

	local bridgeNet = require(assets.Modules.BridgeNet)
	local fallDamage = bridgeNet.CreateBridge("FallDamage")

	humanoid.Died:Connect(function()
		fallDamage:Destroy()
		dead = true
	end)

	local rayParams = RaycastParams.new()
	rayParams.IgnoreWater = false
	rayParams.RespectCanCollide = false
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	local distance = -3.1
	local fallingDist = 0
	local airborne = false
	runService.RenderStepped:Connect(function()
		if dead then
			return
		end
		if humanoid.Sit then
			fallingDist = 0
		end
		local rayResult = workspace:Raycast(humanoidRootPart.Position, Vector3.new(0, distance, 0), rayParams)
		if rayResult and rayResult.Instance and not script:GetAttribute("Override") then
			if airborne then
				airborne = false
				character:SetAttribute("Airborne", false)
				if fallingDist > config.fallDamageDist then
					local damage = humanoidRootPart.AssemblyLinearVelocity.Magnitude * config.fallDamageMultiplier
					fallDamage:Fire(damage)
				end
				fallingDist = 0
			end
		else
			airborne = true
			character:SetAttribute("Airborne", true)
		end

		local curHeight = humanoidRootPart.Position.Y
		if curHeight < prevHeight and airborne then
			fallingDist += prevHeight - curHeight
		else
			fallingDist = 0
		end
		prevHeight = curHeight
	end)

	humanoid.Climbing:Connect(function()
		fallingDist = 0
	end)

	humanoid.Swimming:Connect(function()
		fallingDist = 0
	end)
end
