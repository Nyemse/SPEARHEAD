local module = {}

-- Return true if this part is an R6 body part, excluding the HumanoidRootPart.
module.IsR6BodyPart = function(part)
	return part.Name == "Left Arm"
		or part.Name == "Right Arm"
		or part.Name == "Left Leg"
		or part.Name == "Right Leg"
		or part.Name == "Head"
		or part.Name == "Torso"
end

-- Fires a "hitscan bullet" by raycasting in a direction while ignoring parts that would be ignored by a normal bullet.
module.FireHitscanBullet = function(
	firePoint: Vector3,
	direction: Vector3,
	maxDistance: number,
	ignoreList,
	loop: number
)
	if loop and loop >= 4 then
		return
	end -- Prevent function from looping too many times

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = ignoreList
	rayParams.RespectCanCollide = false

	local rayResult = workspace:Raycast(firePoint, direction * maxDistance, rayParams)
	local hitPart = rayResult and rayResult.Instance
	if hitPart then
		if
			hitPart:HasTag("SPH_NoCollide")
			or hitPart.Parent:IsA("Accessory")
			or hitPart.Transparency >= 1
			or (not hitPart.CanCollide and not module.IsR6BodyPart(hitPart))
		then -- Ray needs to pass through this part!
			table.insert(ignoreList, hitPart)
			return module.FireHitscanBullet(firePoint, direction, maxDistance, ignoreList, loop and loop + 1 or 1)
		else -- Ray hit a part!
			return rayResult
		end
	end
end

return module
