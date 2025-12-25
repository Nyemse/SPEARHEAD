--[[

FractureGlass by MrTumbleWede

FractureGlass(part, origin, force)
	part: BasePart
		The glass we want to fracture
	origin: Vector3?
		The center point of where the glass will break
		Default: part.Position
	force: Vector3?
		The velocity that will be applied to the glass fragments
		It's highly recommended that you use this parameter so the glass can fall more easily
		Default: Vector3.zero

Notes:
	Images on the glass will disappear when the function is called on the glass.
	UnionOperations and MeshParts can technically be used on this function, but it will treat them like a regular part, so it's strongly not recommended.
	This function has another parameter called ..., but you can just ignore that. It's used so we can create the fragments on the client if we call it on the server.
	This module technically works on the client, but you should still call it on the server so it gets destroyed on the server and replicates for everyone.
		This isn't as important if your game is single player.
]]

---------- Settings ----------

local numCracks = 6 -- Must be at least 4 (wouldn't recommend more than 6) | How many cracks we want
local diameter = 1 -- Must be greater than 0 (wouldn't recommend less than 1) | The starting diameter of the cracks. Each crack changes direction when it reaches this diameter.
local multiplier = 2 -- Must be greater than 1 (wouldn't recommend less than 2) | When the crack changes direction, the diameter gets multiplied by this value.
local lifetime = require(game.ReplicatedStorage.SPH_Assets.GameConfig).glassShardDespawnTime -- How many seconds we want the glass to last before getting destroyed
local soundId = 0 -- Set to 0 if you want no sound | The glass break sound effect
local soundVolume = 1 -- Volume of the glass breaking sound effect
local tweenStyle = 0 -- 0 for no animation, 1 for fading away, 2 for shrinking away, and 3 for both. | The tween effect that will be applied to the glass fragments
local tweenDelay = 2 -- How long we wait in seconds until we begin the tweening
local weldTriangles = false -- Each triangle is made up of two wedges. This decides if we wan't to weld the two wedges together or not.
local canCollide = true -- Decides if the glass fragments will be collidable or not
local replicate = true -- Module can't be in ServerScriptService or ServerStorage if set to true | Decides if we want to create the glass fragments on the client to remove the physics delay.
local parent = game.Workspace.Terrain -- Where we want to parent the glass fragments and sound to be

------------------------------

local tweenAnimation = {}
if tweenStyle == 1 or tweenStyle == 3 then
	tweenAnimation.Transparency = 1
end
if tweenStyle == 2 or tweenStyle == 3 then
	tweenAnimation.Size = Vector3.new()
end
local sound

if soundId ~= 0 and (not replicate or replicate and not game.Players.LocalPlayer) then
	sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. soundId
	sound.Volume = soundVolume
	sound.PlayOnRemove = true
	sound.Parent = parent -- Set the parent of the sound so it can load
end

-- 3D Triangles by EgoMoose
local wedge = Instance.new("WedgePart")
wedge.Name = "GlassFragment"
wedge.Anchored = true
wedge.CanCollide = canCollide
wedge.CanTouch = false
wedge.TopSurface = Enum.SurfaceType.Smooth
wedge.BottomSurface = Enum.SurfaceType.Smooth

local function DrawTriangle(a, b, c, part, force)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)

	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end

	ab, ac, bc = b - a, c - a, c - b

	local right = ac:Cross(ab).unit
	local up = bc:Cross(right).unit
	local back = bc.unit
	local height = math.abs(ab:Dot(up))

	local w1 = wedge:Clone()
	w1.Size = Vector3.new(part.Size.Z, height, math.abs(ab:Dot(back)))
	w1.CFrame = part.CFrame
		* CFrame.new((a + b) * 0.5 - part.Position)
		* CFrame.fromMatrix(Vector3.new(), right, up, back)
	w1.Color = part.Color
	w1.Material = part.Material
	w1.Transparency = part.Transparency
	w1.CastShadow = part.CastShadow
	w1.Velocity = force
	w1.Parent = parent

	local w2 = wedge:Clone()
	w2.Size = Vector3.new(part.Size.Z, height, math.abs(ac:Dot(back)))
	w2.CFrame = part.CFrame
		* CFrame.new((a + c) * 0.5 - part.Position)
		* CFrame.fromMatrix(Vector3.new(), -right, up, -back)
	w2.Color = part.Color
	w2.Material = part.Material
	w2.Transparency = part.Transparency
	w2.CastShadow = part.CastShadow
	w2.Velocity = force
	w2.Parent = parent

	if weldTriangles then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = w1
		weld.Part1 = w2
		weld.Parent = w1
	end

	return w1, w2
end

-- Sutherland-Hodgman Polygon Clipping Algorithm
local function FindIntersectionV(a, b, x)
	return a:Lerp(b, (a.X - x) / (a.X - b.X))
end

local function FindIntersectionH(a, b, y)
	return a:Lerp(b, (a.Y - y) / (a.Y - b.Y))
end

local function FindIntersectionD(a, b, am, ab)
	local bm = (b.Y - a.Y) / (b.X - a.X)
	local bb = a.Y - a.X * bm
	local x = (ab - bb) / (bm - am)
	return Vector3.new(x, x * am + ab, a.Z)
end

local function CreatePolygon(points, part, force)
	local halfSize = part.Size * 0.5
	local newPoints = {}
	local top, bottom, left, right =
		part.Position.Y + halfSize.Y,
		part.Position.Y - halfSize.Y,
		part.Position.X - halfSize.X,
		part.Position.X + halfSize.X

	if part.Shape == Enum.PartType.Wedge then
		-- Clip Hypotenuse
		local a, b =
			Vector2.new(part.Position.X - halfSize.X, part.Position.Y + halfSize.Y),
			Vector2.new(part.Position.X + halfSize.X, part.Position.Y - halfSize.Y)
		local m = (b.Y - a.Y) / (b.X - a.X)
		local offset = a.Y - a.X * m

		for i, a in ipairs(points) do
			local b = points[i % #points + 1]
			local isA, isB = a.Y <= a.X * m + offset, b.Y <= b.X * m + offset

			if isA and isB then
				table.insert(newPoints, b)
			elseif not isA and isB then
				table.insert(newPoints, FindIntersectionD(a, b, m, offset))
				table.insert(newPoints, b)
			elseif isA and not isB then
				table.insert(newPoints, FindIntersectionD(a, b, m, offset))
			end
		end
	else
		-- Clip right

		for i, a in ipairs(points) do
			local b = points[i % #points + 1]
			local isA, isB = a.X <= right, b.X <= right

			if isA and isB then
				table.insert(newPoints, b)
			elseif not isA and isB then
				table.insert(newPoints, FindIntersectionV(a, b, right))
				table.insert(newPoints, b)
			elseif isA and not isB then
				table.insert(newPoints, FindIntersectionV(a, b, right))
			end
		end

		-- Clip top
		points = newPoints
		newPoints = {}

		for i, a in ipairs(points) do
			local b = points[i % #points + 1]
			local isA, isB = a.Y <= top, b.Y <= top

			if isA and isB then
				table.insert(newPoints, b)
			elseif not isA and isB then
				table.insert(newPoints, FindIntersectionH(a, b, top))
				table.insert(newPoints, b)
			elseif isA and not isB then
				table.insert(newPoints, FindIntersectionH(a, b, top))
			end
		end
	end

	points = newPoints
	newPoints = {}

	-- Clip left
	for i, a in ipairs(points) do
		local b = points[i % #points + 1]
		local isA, isB = a.X >= left, b.X >= left

		if isA and isB then
			table.insert(newPoints, b)
		elseif not isA and isB then
			table.insert(newPoints, FindIntersectionV(a, b, left))
			table.insert(newPoints, b)
		elseif isA and not isB then
			table.insert(newPoints, FindIntersectionV(a, b, left))
		end
	end

	---- Clip bottom
	points = newPoints
	newPoints = {}

	for i, a in ipairs(points) do
		local b = points[i % #points + 1]
		local isA, isB = a.Y >= bottom, b.Y >= bottom

		if isA and isB then
			table.insert(newPoints, b)
		elseif not isA and isB then
			table.insert(newPoints, FindIntersectionH(a, b, bottom))
			table.insert(newPoints, b)
		elseif isA and not isB then
			table.insert(newPoints, FindIntersectionH(a, b, bottom))
		end
	end

	-- Draw polygon
	local triangles = {}

	for i = 3, #newPoints do
		local w1, w2 = DrawTriangle(newPoints[1], newPoints[i - 1], newPoints[i], part, force)
		table.insert(triangles, w1)
		table.insert(triangles, w2)
	end

	return triangles
end

local function IsInCircle(point, circle, radius)
	return (point.X - circle.X) ^ 2 + (point.Y - circle.Y) ^ 2 < radius * radius
end

local function CreateCracks(part, origin, force)
	local triangles = {}
	local halfSize = part.Size * 0.5

	local points = {}
	local rings = 1
	local angle = math.pi * 2 / numCracks
	local doubleSize = diameter
	local point = Vector2.new(math.cos(angle * 1.5), math.sin(angle * 1.5))
	local safezone = (point * 0.5 + Vector2.new(0.5, 0)).Magnitude -- Ensures that the glass isn't outside the segment but inside the diameter

	while true do
		rings += 1
		doubleSize *= multiplier

		if
			IsInCircle(part.Position + Vector3.new(-halfSize.X, -halfSize, 0), origin, doubleSize * safezone)
			and IsInCircle(part.Position + Vector3.new(-halfSize.X, halfSize.Y, 0), origin, doubleSize * safezone)
			and IsInCircle(part.Position + Vector3.new(halfSize.X, halfSize.Y, 0), origin, doubleSize * safezone)
			and IsInCircle(part.Position + Vector3.new(halfSize.X, -halfSize.Y, 0), origin, doubleSize * safezone)
		then
			break
		end
	end

	for i = 1, numCracks do
		points[i] = {}

		for j = 1, rings do
			local angle = angle * (i + (math.random() - 0.5) * 0.5)
			points[i][j] = angle
		end
	end

	for i = 1, numCracks do
		for j = 1, rings do
			local iMinusOne = (numCracks + i - 2) % numCracks + 1

			if j == 1 then
				local p1, p2 =
					(CFrame.new(origin) * CFrame.Angles(0, 0, points[i][j]) * CFrame.new(0, diameter, 0)).Position,
					(CFrame.new(origin) * CFrame.Angles(0, 0, points[iMinusOne][j]) * CFrame.new(0, diameter, 0)).Position

				for i, v in ipairs(CreatePolygon({ origin, p1, p2 }, part, force)) do
					table.insert(triangles, v)
					v.Anchored = false
				end
			else
				local p1, p2, p3, p4 =
					(CFrame.new(origin) * CFrame.Angles(0, 0, points[i][j]) * CFrame.new(
						0,
						diameter * multiplier ^ (j - 1),
						0
					)).Position,
					(CFrame.new(origin) * CFrame.Angles(0, 0, points[i][j - 1]) * CFrame.new(
						0,
						diameter * multiplier ^ (j - 2),
						0
					)).Position,
					(CFrame.new(origin) * CFrame.Angles(0, 0, points[iMinusOne][j - 1]) * CFrame.new(
						0,
						diameter * multiplier ^ (j - 2),
						0
					)).Position,
					(CFrame.new(origin) * CFrame.Angles(0, 0, points[iMinusOne][j]) * CFrame.new(
						0,
						diameter * multiplier ^ (j - 1),
						0
					)).Position

				local tris = CreatePolygon({ p1, p2, p3, p4 }, part, force)

				for i, v in ipairs(tris) do
					table.insert(triangles, v)
				end

				task.delay((i - 1) * 0.015 + j * 0.005, function()
					for i, v in ipairs(tris) do
						v.Anchored = false
					end
				end)
			end
		end
	end

	return triangles, (numCracks - 1) * 0.015 + rings * 0.005
end

return function(part, origin, force, ...)
	if not ... then
		-- Check parameters
		assert(part, "Parameter 'part' was nil, expected BasePart.")
		origin = origin or part.Position
		force = force or Vector3.new()

		-- Resize part so thin side is the z-axis
		if part.Shape == Enum.PartType.Wedge then
			part.Size = Vector3.new(part.Size.Z, part.Size.Y, part.Size.X)
			part.CFrame *= CFrame.Angles(0, math.pi * 0.5, 0)
		else
			local min = math.min(part.Size.X, part.Size.Y, part.Size.Z)

			if min == part.Size.X then
				part.Size = Vector3.new(part.Size.Z, part.Size.Y, part.Size.X)
				part.CFrame *= CFrame.Angles(0, math.pi * 0.5, 0)
			elseif min == part.Size.Y then
				part.Size = Vector3.new(part.Size.X, part.Size.Z, part.Size.Y)
				part.CFrame *= CFrame.Angles(math.pi * 0.5, 0, 0)
			end
		end

		-- Move origin to part surface
		local offset = (part.CFrame:ToObjectSpace(CFrame.new(origin))).Position
		origin = offset + part.Position
		origin = Vector3.new(origin.X, origin.Y, part.Position.Z)

		if sound then
			sound:Clone().Parent = part
		end
	end

	if not game.Players.LocalPlayer and replicate and not ... then -- Called on the server
		script:WaitForChild("RenderGlass"):FireAllClients({
			Position = part.Position,
			CFrame = part.CFrame,
			Size = part.Size,
			Color = part.Color,
			Material = part.Material,
			Transparency = part.Transparency,
			CastShadow = part.CastShadow,
			Shape = part.Shape,
		}, origin, force)
		part:Destroy()
	else -- Called on the client or replicate is false
		local triangles, anchorDelay = CreateCracks(part, origin, force)
		local destroyed = false

		task.delay(lifetime, function()
			for i, v in ipairs(triangles) do
				v:Destroy()
			end
			destroyed = true
		end)

		if tweenStyle ~= 0 then
			task.delay(tweenDelay, function()
				for i, v in ipairs(triangles) do
					game.TweenService
						:Create(v, TweenInfo.new(lifetime - tweenDelay, Enum.EasingStyle.Linear), tweenAnimation)
						:Play()
				end
			end)
		end

		-- Anchor inactive wedges to reduce lag
		if canCollide then
			task.delay(anchorDelay + 0.1, function()
				local tris = table.clone(triangles)

				while not destroyed do
					for i = #tris, 1, -1 do
						local v = tris[i]

						if v.Velocity.Y < math.min(-1 + (v.Size.X + v.Size.Y) * 0.1, 0) and not v.Anchored then
							continue
						end
						v.Anchored = true
						v.CanCollide = false
						table.remove(tris, i)
					end

					task.wait(0.1)
				end
			end)
		end

		if typeof(part) ~= "table" then
			part:Destroy()
		end
	end
end
