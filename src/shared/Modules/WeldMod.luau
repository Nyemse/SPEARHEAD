local weldMod = {}

-- Constrains two parts with a Weld
weldMod.Weld = function(p0, p1)
	local nWeld = Instance.new("Weld")
	nWeld.Part0 = p0
	nWeld.Part1 = p1
	nWeld.C0 = p0.CFrame:ToObjectSpace(p1.CFrame)
	nWeld.Name = p0.Name .. "_" .. p1.Name
	nWeld.Parent = p0
	p1.Anchored = false
	return nWeld
end

-- Constrains two parts with a Motor6D
weldMod.M6D = function(p0, p1)
	local nWeld = Instance.new("Motor6D")
	nWeld.Part0 = p0
	nWeld.Part1 = p1
	nWeld.C0 = p0.CFrame:ToObjectSpace(p1.CFrame)
	nWeld.Name = p0.Name .. "_" .. p1.Name
	nWeld.Parent = p0
	p1.Anchored = false
	return nWeld
end

weldMod.BlankM6D = function(p0, p1)
	local nWeld = Instance.new("Motor6D")
	nWeld.Part0 = p0
	nWeld.Part1 = p1
	nWeld.Name = p0.Name .. "_" .. p1.Name
	nWeld.Parent = p0
	p1.Anchored = false
	return nWeld
end

-- Welds all children of model to base
weldMod.WeldModel = function(model, base, collision)
	for _, cPart in ipairs(model:GetChildren()) do
		if cPart:IsA("BasePart") and cPart ~= base then
			weldMod.Weld(base, cPart)
			cPart.CanCollide = collision
		end
	end
end

-- Welds all descendant parts of model
weldMod.WeldDescendants = function(model, base, collision)
	for _, cPart in ipairs(model:GetDescendants()) do
		if cPart:IsA("BasePart") and cPart ~= base then
			weldMod.Weld(base, cPart)
			cPart.CanCollide = collision
		end
	end
end

-- Weld parts to a base or to its parent part if it doesn't have an existing constraint
weldMod.AutoWeldModel = function(model, base, noCol, ignoreParts)
	--for _, dPart in ipairs(model:GetDescendants()) do
	--	if dPart:IsA("Weld") or dPart:IsA("Constraint") then
	--		print(dPart.Name)
	--	end
	--end

	for _, cPart: BasePart in ipairs(model:GetChildren()) do
		if cPart:IsA("BasePart") and cPart ~= base and not table.find(ignoreParts, cPart.Name) then
			weldMod.Weld(base, cPart)

			--local partJoints = cPart:GetJoints()

			--if #partJoints == 0 then
			--	weldMod.Weld(base,cPart)
			--	if cPart.Parent:IsA("BasePart") then
			--		--print(cPart.Name, #partJoints)
			--	end
			--end

			if noCol then
				cPart.CanCollide = false
			end
			weldMod.AutoWeldModel(cPart, cPart, noCol)
		end
	end
end

-- Creates a blank weld with no c0 or c1
weldMod.BlankWeld = function(p0, p1)
	local newWeld = Instance.new("Weld")
	newWeld.Part0 = p0
	newWeld.Part1 = p1
	newWeld.Name = p0.Name .. "_" .. p1.Name
	newWeld.Parent = p0
	p1.Anchored = false
	return newWeld
end

return weldMod
