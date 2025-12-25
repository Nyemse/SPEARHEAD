--!nocheck
-- ^ change to strict to crash studio c:
-- ActiveCast class type.
-- The ActiveCast type represents a currently running cast.

-----------------------------------------------------------
--------------------- TYPE DEFINITION ---------------------
-----------------------------------------------------------

-- This will inject all types into this context.
local TypeDefs = require(script.Parent.TypeDefinitions)

type CanPierceFunction = TypeDefs.CanPierceFunction
type GenericTable = TypeDefs.GenericTable
type Caster = TypeDefs.Caster
type FastCastBehavior = TypeDefs.FastCastBehavior
type CastTrajectory = TypeDefs.CastTrajectory
type CastStateInfo = TypeDefs.CastStateInfo
type CastRayInfo = TypeDefs.CastRayInfo
type ActiveCast = TypeDefs.ActiveCast

local typeof = require(script.Parent.TypeMarshaller)

-----------------------------------------------------------
-------------------- MODULE DEFINITION --------------------
-----------------------------------------------------------

local ActiveCastStatic = {}
ActiveCastStatic.__index = ActiveCastStatic
ActiveCastStatic.__type = "ActiveCast" -- For compatibility with TypeMarshaller

-----------------------------------------------------------
----------------------- STATIC DATA -----------------------
-----------------------------------------------------------
local RunService = game:GetService("RunService")
local table = require(script.Parent.Table)
local FastCast = nil -- Static reference to the FastCast static module.

-- Format params: methodName, ctorName
local ERR_NOT_INSTANCE =
	"Cannot statically invoke method '%s' - It is an instance method. Call it on an instance of this class created via %s"

-- Format params: paramName, expectedType, actualType
local ERR_INVALID_TYPE = "Invalid type for parameter '%s' (Expected %s, got %s)"

-- The name of the folder containing the 3D GUI elements for visualizing casts in debug mode.
local FC_VIS_OBJ_NAME = "FastCastVisualizationObjects"

-- Format params: N/A
local ERR_OBJECT_DISPOSED = "This ActiveCast has been terminated. It can no longer be used."

-- If pierce callback has to run more than this many times, it will register a hit and stop calculating pierces.
-- This only applies for repeated piercings, e.g. the amount of parts that fit within the space of a single cast segment (NOT the whole bullet's trajectory over its entire lifetime)
local MAX_PIERCE_TEST_COUNT = 100

-----------------------------------------------------------
------------------------ UTILITIES ------------------------
-----------------------------------------------------------

-- Looks for a folder within workspace.Terrain that contains elements to visualize casts.
local function GetFastCastVisualizationContainer(): Instance
	local fcVisualizationObjects = workspace.Terrain:FindFirstChild(FC_VIS_OBJ_NAME)
	if fcVisualizationObjects ~= nil then
		return fcVisualizationObjects
	end

	fcVisualizationObjects = Instance.new("Folder")
	fcVisualizationObjects.Name = FC_VIS_OBJ_NAME
	fcVisualizationObjects.Archivable = false -- TODO: Keep this as-is? You can't copy/paste it if this is false. I have it false so that it doesn't linger in studio if you save with the debug data in there.
	fcVisualizationObjects.Parent = workspace.Terrain
	return fcVisualizationObjects
end

-----------------------------------------------------------
------------------------ DEBUGGING ------------------------
-----------------------------------------------------------

-- Print that runs only if debug mode is active.
local function PrintDebug(message: string)
	if FastCast.DebugLogging == true then
		print(message)
	end
end

-- Visualizes a ray. This will not run if FastCast.VisualizeCasts is false.
function DbgVisualizeSegment(castStartCFrame: CFrame, castLength: number): ConeHandleAdornment?
	if FastCast.VisualizeCasts ~= true then
		return nil
	end
	local adornment = Instance.new("ConeHandleAdornment")
	adornment.Adornee = workspace.Terrain
	adornment.CFrame = castStartCFrame
	adornment.Height = castLength
	adornment.Color3 = Color3.new()
	adornment.Radius = 0.25
	adornment.Transparency = 0.5
	adornment.Parent = GetFastCastVisualizationContainer()
	return adornment
end

-- Visualizes an impact. This will not run if FastCast.VisualizeCasts is false.
function DbgVisualizeHit(atCF: CFrame, wasPierce: boolean): SphereHandleAdornment?
	if FastCast.VisualizeCasts ~= true then
		return nil
	end
	local adornment = Instance.new("SphereHandleAdornment")
	adornment.Adornee = workspace.Terrain
	adornment.CFrame = atCF
	adornment.Radius = 0.4
	adornment.Transparency = 0.25
	adornment.Color3 = (wasPierce == false) and Color3.new(0.2, 1, 0.5) or Color3.new(1, 0.2, 0.2)
	adornment.Parent = GetFastCastVisualizationContainer()
	return adornment
end

-----------------------------------------------------------
------------------------ CORE CODE ------------------------
-----------------------------------------------------------

-- Thanks to zoebasil for supplying the velocity and position functions below. (I've modified these functions)
-- I was having a huge issue trying to get it to work and I had overcomplicated a bunch of stuff.
-- GetPositionAtTime is used in physically simulated rays (Where Caster.HasPhysics == true or the specific Fire has a specified acceleration).
-- This returns the location that the bullet will be at when you specify the amount of time the bullet has existed, the original location of the bullet, and the velocity it was launched with.
local function GetPositionAtTime(
	time: number,
	origin: Vector3,
	initialVelocity: Vector3,
	acceleration: Vector3
): Vector3
	local force =
		Vector3.new((acceleration.X * time ^ 2) / 2, (acceleration.Y * time ^ 2) / 2, (acceleration.Z * time ^ 2) / 2)
	return origin + (initialVelocity * time) + force
end

-- A variant of the function above that returns the velocity at a given point in time.
local function GetVelocityAtTime(time: number, initialVelocity: Vector3, acceleration: Vector3): Vector3
	return initialVelocity + acceleration * time
end

local function GetTrajectoryInfo(cast: ActiveCast, index: number): { [number]: Vector3 }
	assert(cast.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)
	local trajectories = cast.StateInfo.Trajectories
	local trajectory = trajectories[index]
	local duration = trajectory.EndTime - trajectory.StartTime

	local origin = trajectory.Origin
	local vel = trajectory.InitialVelocity
	local accel = trajectory.Acceleration

	return { GetPositionAtTime(duration, origin, vel, accel), GetVelocityAtTime(duration, vel, accel) }
end

local function GetLatestTrajectoryEndInfo(cast: ActiveCast): { [number]: Vector3 }
	assert(cast.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)
	return GetTrajectoryInfo(cast, #cast.StateInfo.Trajectories)
end

local function CloneCastParams(params: RaycastParams): RaycastParams
	local clone = RaycastParams.new()
	clone.CollisionGroup = params.CollisionGroup
	clone.FilterType = params.FilterType
	clone.FilterDescendantsInstances = params.FilterDescendantsInstances
	clone.IgnoreWater = params.IgnoreWater
	return clone
end

local function SendRayHit(
	cast: ActiveCast,
	resultOfCast: RaycastResult,
	segmentVelocity: Vector3,
	cosmeticBulletObject: Instance?
)
	--cast.RayHit:Fire(cast, resultOfCast, segmentVelocity, cosmeticBulletObject)
	cast.Caster.RayHit:Fire(cast, resultOfCast, segmentVelocity, cosmeticBulletObject)
end

local function SendRayPierced(
	cast: ActiveCast,
	resultOfCast: RaycastResult,
	segmentVelocity: Vector3,
	cosmeticBulletObject: Instance?
)
	--cast.RayPierced:Fire(cast, resultOfCast, segmentVelocity, cosmeticBulletObject)
	cast.Caster.RayPierced:Fire(cast, resultOfCast, segmentVelocity, cosmeticBulletObject)
end

local function SendLengthChanged(
	cast: ActiveCast,
	lastPoint: Vector3,
	rayDir: Vector3,
	rayDisplacement: number,
	segmentVelocity: Vector3,
	cosmeticBulletObject: Instance?
)
	--cast.LengthChanged:Fire(cast, lastPoint, rayDir, rayDisplacement, segmentVelocity, cosmeticBulletObject)
	cast.Caster.LengthChanged:Fire(cast, lastPoint, rayDir, rayDisplacement, segmentVelocity, cosmeticBulletObject)
end

-- Simulate a raycast by one tick.
local function SimulateCast(cast: ActiveCast, delta: number, expectingShortCall: boolean)
	assert(cast.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)
	PrintDebug("Casting for frame.")
	local latestTrajectory = cast.StateInfo.Trajectories[#cast.StateInfo.Trajectories]

	local origin = latestTrajectory.Origin
	local totalDelta = cast.StateInfo.TotalRuntime - latestTrajectory.StartTime
	local initialVelocity = latestTrajectory.InitialVelocity
	local acceleration = latestTrajectory.Acceleration

	local lastPoint = GetPositionAtTime(totalDelta, origin, initialVelocity, acceleration)
	local lastVelocity = GetVelocityAtTime(totalDelta, initialVelocity, acceleration)
	local lastDelta = cast.StateInfo.TotalRuntime - latestTrajectory.StartTime

	cast.StateInfo.TotalRuntime += delta

	-- Recalculate this.
	totalDelta = cast.StateInfo.TotalRuntime - latestTrajectory.StartTime

	local currentTarget = GetPositionAtTime(totalDelta, origin, initialVelocity, acceleration)
	local segmentVelocity = GetVelocityAtTime(totalDelta, initialVelocity, acceleration)
	local totalDisplacement = currentTarget - lastPoint -- This is the displacement from where the ray was on the last from to where the ray is now.

	local rayDir = totalDisplacement.Unit * segmentVelocity.Magnitude * delta
	local targetWorldRoot = cast.RayInfo.WorldRoot
	local resultOfCast = targetWorldRoot:Raycast(lastPoint, rayDir, cast.RayInfo.Parameters)

	local point = currentTarget
	local part: Instance? = nil
	local material = Enum.Material.Air
	local normal = Vector3.new()

	if resultOfCast ~= nil then
		point = resultOfCast.Position
		part = resultOfCast.Instance
		material = resultOfCast.Material
		normal = resultOfCast.Normal
	end

	local rayDisplacement = (point - lastPoint).Magnitude
	-- For clarity -- totalDisplacement is how far the ray would have traveled if it hit nothing,
	-- and rayDisplacement is how far the ray really traveled (which will be identical to totalDisplacement if it did indeed hit nothing)

	SendLengthChanged(cast, lastPoint, rayDir.Unit, rayDisplacement, segmentVelocity, cast.RayInfo.CosmeticBulletObject)
	cast.StateInfo.DistanceCovered += rayDisplacement

	local rayVisualization: ConeHandleAdornment? = nil
	if delta > 0 then
		rayVisualization = DbgVisualizeSegment(CFrame.new(lastPoint, lastPoint + rayDir), rayDisplacement)
	end

	-- HIT DETECTED. Handle all that garbage, and also handle behaviors 1 and 2 (default behavior, go high res when hit) if applicable.
	-- CAST BEHAVIOR 2 IS HANDLED IN THE CODE THAT CALLS THIS FUNCTION.

	if part and part ~= cast.RayInfo.CosmeticBulletObject then
		local start = tick()
		PrintDebug("Hit something, testing now.")

		-- SANITY CHECK: Don't allow the user to yield or run otherwise extensive code that takes longer than one frame/heartbeat to execute.
		if cast.RayInfo.CanPierceCallback ~= nil then
			if expectingShortCall == false then
				if cast.StateInfo.IsActivelySimulatingPierce then
					cast:Terminate()
					error(
						"ERROR: The latest call to CanPierceCallback took too long to complete! This cast is going to suffer desyncs which WILL cause unexpected behavior and errors. Please fix your performance problems, or remove statements that yield (e.g. wait() calls)"
					)
					-- Use error. This should absolutely abort the cast.
				end
			end
			-- expectingShortCall is used to determine if we are doing a forced resolution increase, in which case this will be called several times in a single frame, which throws this error.
			cast.StateInfo.IsActivelySimulatingPierce = true
		end
		------------------------------

		if
			cast.RayInfo.CanPierceCallback == nil
			or (
				cast.RayInfo.CanPierceCallback ~= nil
				and cast.RayInfo.CanPierceCallback(
						cast,
						resultOfCast,
						segmentVelocity,
						cast.RayInfo.CosmeticBulletObject
					)
					== false
			)
		then
			PrintDebug("Piercing function is nil or it returned FALSE to not pierce this hit.")
			cast.StateInfo.IsActivelySimulatingPierce = false

			if
				cast.StateInfo.HighFidelityBehavior == 2
				and latestTrajectory.Acceleration ~= Vector3.new()
				and cast.StateInfo.HighFidelitySegmentSize ~= 0
			then
				cast.StateInfo.CancelHighResCast = false -- Reset this here.

				if cast.StateInfo.IsActivelyResimulating then
					cast:Terminate()
					error(
						"Cascading cast lag encountered! The caster attempted to perform a high fidelity cast before the previous one completed, resulting in exponential cast lag. Consider increasing HighFidelitySegmentSize."
					)
				end

				cast.StateInfo.IsActivelyResimulating = true

				-- This is a physics based cast and it needs to be recalculated.
				PrintDebug(
					"Hit was registered, but recalculation is on for physics based casts. Recalculating to verify a real hit..."
				)

				-- Split this ray segment into smaller segments of a given size.
				-- In 99% of cases, it won't divide evently (e.g. I have a distance of 1.25 and I want to divide into 0.1 -- that won't work)
				-- To fix this, the segments need to be stretched slightly to fill the space (rather than having a single shorter segment at the end)

				local numSegmentsDecimal = rayDisplacement / cast.StateInfo.HighFidelitySegmentSize -- say rayDisplacement is 5.1, segment size is 0.5 -- 10.2 segments
				local numSegmentsReal = math.floor(numSegmentsDecimal) -- 10 segments + 0.2 extra segments
				local realSegmentLength = rayDisplacement / numSegmentsReal -- this spits out 0.51, which isn't exact to the defined 0.5, but it's close

				-- Now the real hard part is converting this to time.
				local timeIncrement = delta / numSegmentsReal
				for segmentIndex = 1, numSegmentsReal do
					if cast.StateInfo.CancelHighResCast then
						cast.StateInfo.CancelHighResCast = false
						break
					end

					local subPosition = GetPositionAtTime(
						lastDelta + (timeIncrement * segmentIndex),
						origin,
						initialVelocity,
						acceleration
					)
					local subVelocity =
						GetVelocityAtTime(lastDelta + (timeIncrement * segmentIndex), initialVelocity, acceleration)
					local subRayDir = subVelocity * delta
					local subResult = targetWorldRoot:Raycast(subPosition, subRayDir, cast.RayInfo.Parameters)

					local subDisplacement = (subPosition - (subPosition + subVelocity)).Magnitude

					if subResult ~= nil then
						local subDisplacement = (subPosition - subResult.Position).Magnitude
						local dbgSeg =
							DbgVisualizeSegment(CFrame.new(subPosition, subPosition + subVelocity), subDisplacement)
						if dbgSeg ~= nil then
							dbgSeg.Color3 = Color3.new(0.286275, 0.329412, 0.247059)
						end

						if
							cast.RayInfo.CanPierceCallback == nil
							or (
								cast.RayInfo.CanPierceCallback ~= nil
								and cast.RayInfo.CanPierceCallback(
										cast,
										subResult,
										subVelocity,
										cast.RayInfo.CosmeticBulletObject
									)
									== false
							)
						then
							-- Still hit even at high res
							cast.StateInfo.IsActivelyResimulating = false

							SendRayHit(cast, subResult, subVelocity, cast.RayInfo.CosmeticBulletObject)
							cast:Terminate()
							local vis = DbgVisualizeHit(CFrame.new(point), false)
							if vis ~= nil then
								vis.Color3 = Color3.new(0.0588235, 0.87451, 1)
							end
							return
						else
							-- Recalculating hit something pierceable instead.
							SendRayPierced(cast, subResult, subVelocity, cast.RayInfo.CosmeticBulletObject) -- This may result in CancelHighResCast being set to true.
							local vis = DbgVisualizeHit(CFrame.new(point), true)
							if vis ~= nil then
								vis.Color3 = Color3.new(1, 0.113725, 0.588235)
							end
							if dbgSeg ~= nil then
								dbgSeg.Color3 = Color3.new(0.305882, 0.243137, 0.329412)
							end
						end
					else
						local dbgSeg =
							DbgVisualizeSegment(CFrame.new(subPosition, subPosition + subVelocity), subDisplacement)
						if dbgSeg ~= nil then
							dbgSeg.Color3 = Color3.new(0.286275, 0.329412, 0.247059)
						end
					end
				end

				-- If the script makes it here, then it wasn't a real hit (higher resolution revealed that the low-res hit was faulty)
				-- Just let it keep going.
				cast.StateInfo.IsActivelyResimulating = false
			elseif cast.StateInfo.HighFidelityBehavior ~= 1 and cast.StateInfo.HighFidelityBehavior ~= 3 then
				cast:Terminate()
				error("Invalid value " .. cast.StateInfo.HighFidelityBehavior .. " for HighFidelityBehavior.")
			else
				-- This is not a physics cast, or recalculation is off.
				PrintDebug("Hit was successful. Terminating.")
				SendRayHit(cast, resultOfCast, segmentVelocity, cast.RayInfo.CosmeticBulletObject)
				cast:Terminate()
				DbgVisualizeHit(CFrame.new(point), false)
				return
			end
		else
			PrintDebug("Piercing function returned TRUE to pierce this part.")
			if rayVisualization ~= nil then
				rayVisualization.Color3 = Color3.new(0.4, 0.05, 0.05) -- Turn it red to signify that the cast was scrapped.
			end
			DbgVisualizeHit(CFrame.new(point), true)

			local params = cast.RayInfo.Parameters
			local alteredParts = {}
			local currentPierceTestCount = 0
			local originalFilter = params.FilterDescendantsInstances
			local brokeFromSolidObject = false
			while true do
				-- So now what I need to do is redo this entire cast, just with the new filter list

				-- Catch case: Is it terrain?
				--if resultOfCast.Instance:IsA("Terrain") then
				--	if material == Enum.Material.Water then
				--		-- Special case: Pierced on water?
				--		cast:Terminate()
				--		error("Do not add Water as a piercable material. If you need to pierce water, set cast.RayInfo.Parameters.IgnoreWater = true instead", 0)
				--	end
				--	warn("WARNING: The pierce callback for this cast returned TRUE on Terrain! This can cause severely adverse effects.")
				--end

				if params.FilterType == Enum.RaycastFilterType.Blacklist then
					-- blacklist
					-- DO NOT DIRECTLY TABLE.INSERT ON THE PROPERTY
					local filter = params.FilterDescendantsInstances
					table.insert(filter, resultOfCast.Instance)
					table.insert(alteredParts, resultOfCast.Instance)
					params.FilterDescendantsInstances = filter
				else
					-- whitelist
					-- method implemeneted by custom table system
					-- DO NOT DIRECTLY TABLE.REMOVEOBJECT ON THE PROPERTY
					local filter = params.FilterDescendantsInstances
					table.removeObject(filter, resultOfCast.Instance)
					table.insert(alteredParts, resultOfCast.Instance)
					params.FilterDescendantsInstances = filter
				end

				SendRayPierced(cast, resultOfCast, segmentVelocity, cast.RayInfo.CosmeticBulletObject)

				-- List has been updated, so let's cast again.
				resultOfCast = targetWorldRoot:Raycast(lastPoint, rayDir, params)

				-- No hit? No simulation. Break.
				if resultOfCast == nil then
					break
				end

				if currentPierceTestCount >= MAX_PIERCE_TEST_COUNT then
					warn(
						"WARNING: Exceeded maximum pierce test budget for a single ray segment (attempted to test the same segment "
							.. MAX_PIERCE_TEST_COUNT
							.. " times!)"
					)
					break
				end
				currentPierceTestCount = currentPierceTestCount + 1

				if
					cast.RayInfo.CanPierceCallback(
						cast,
						resultOfCast,
						segmentVelocity,
						cast.RayInfo.CosmeticBulletObject
					) == false
				then
					brokeFromSolidObject = true
					break
				end
			end

			-- Restore the filter to its default state.
			cast.RayInfo.Parameters.FilterDescendantsInstances = originalFilter
			cast.StateInfo.IsActivelySimulatingPierce = false

			if brokeFromSolidObject then
				-- We actually hit something while testing.
				PrintDebug(
					"Broke because the ray hit something solid ("
						.. tostring(resultOfCast.Instance)
						.. ") while testing for a pierce. Terminating the cast."
				)
				SendRayHit(cast, resultOfCast, segmentVelocity, cast.RayInfo.CosmeticBulletObject)
				cast:Terminate()
				DbgVisualizeHit(CFrame.new(resultOfCast.Position), false)
				return
			end

			-- And exit the function here too.
		end
	end

	if cast.StateInfo.DistanceCovered >= cast.RayInfo.MaxDistance then
		-- SendRayHit(cast, nil, segmentVelocity, cast.RayInfo.CosmeticBulletObject)
		cast:Terminate()
		DbgVisualizeHit(CFrame.new(currentTarget), false)
	end
end

-----------------------------------------------------------
------------------------- EXPORTS -------------------------
-----------------------------------------------------------

-- Ctor
function ActiveCastStatic.new(
	caster: Caster,
	origin: Vector3,
	direction: Vector3,
	velocity: Vector3 | number,
	castDataPacket: FastCastBehavior
): ActiveCast
	if typeof(velocity) == "number" then
		velocity = direction.Unit * velocity
	end

	if castDataPacket.HighFidelitySegmentSize <= 0 then
		error("Cannot set FastCastBehavior.HighFidelitySegmentSize <= 0!", 0)
	end

	-- Basic setup
	local cast = {
		Caster = caster,

		-- Data that keeps track of what's going on as well as edits we might make during runtime.
		StateInfo = {
			UpdateConnection = nil,
			Paused = false,
			TotalRuntime = 0,
			DistanceCovered = 0,
			HighFidelitySegmentSize = castDataPacket.HighFidelitySegmentSize,
			HighFidelityBehavior = castDataPacket.HighFidelityBehavior,
			IsActivelySimulatingPierce = false,
			IsActivelyResimulating = false,
			CancelHighResCast = false,
			Trajectories = {
				{
					StartTime = 0,
					EndTime = -1,
					Origin = origin,
					InitialVelocity = velocity,
					Acceleration = castDataPacket.Acceleration,
				},
			},
		},

		-- Information pertaining to actual raycasting.
		RayInfo = {
			Parameters = castDataPacket.RaycastParams,
			WorldRoot = workspace,
			MaxDistance = castDataPacket.MaxDistance or 1000,
			CosmeticBulletObject = castDataPacket.CosmeticBulletTemplate, -- This is intended. We clone it a smidge of the way down.
			CanPierceCallback = castDataPacket.CanPierceFunction,
		},

		UserData = {},
	}

	if cast.StateInfo.HighFidelityBehavior == 2 then
		cast.StateInfo.HighFidelityBehavior = 3
	end

	if cast.RayInfo.Parameters ~= nil then
		cast.RayInfo.Parameters = CloneCastParams(cast.RayInfo.Parameters)
	else
		cast.RayInfo.Parameters = RaycastParams.new()
	end

	local usingProvider = false
	if castDataPacket.CosmeticBulletProvider == nil then
		-- The provider is nil. Use a cosmetic object clone.
		if cast.RayInfo.CosmeticBulletObject ~= nil then
			cast.RayInfo.CosmeticBulletObject = cast.RayInfo.CosmeticBulletObject:Clone()
			cast.RayInfo.CosmeticBulletObject.CFrame = CFrame.new(origin, origin + direction)
			cast.RayInfo.CosmeticBulletObject.Parent = castDataPacket.CosmeticBulletContainer
		end
	else
		-- The provider is not nil.
		-- Is it what we want?
		if typeof(castDataPacket.CosmeticBulletProvider) == "PartCache" then
			-- this modded version of typeof is implemented up top.
			-- Aside from that, yes, it's a part cache. Good to go!

			if cast.RayInfo.CosmeticBulletObject ~= nil then
				-- They also set the template. Not good. Warn + clear this up.
				warn(
					"Do not define FastCastBehavior.CosmeticBulletTemplate and FastCastBehavior.CosmeticBulletProvider at the same time! The provider will be used, and CosmeticBulletTemplate will be set to nil."
				)
				cast.RayInfo.CosmeticBulletObject = nil
				castDataPacket.CosmeticBulletTemplate = nil
			end

			cast.RayInfo.CosmeticBulletObject = castDataPacket.CosmeticBulletProvider:GetPart()
			cast.RayInfo.CosmeticBulletObject.CFrame = CFrame.new(origin, origin + direction)
			usingProvider = true
		else
			warn(
				"FastCastBehavior.CosmeticBulletProvider was not an instance of the PartCache module (an external/separate model)! Are you inputting an instance created via PartCache.new? If so, are you on the latest version of PartCache? Setting FastCastBehavior.CosmeticBulletProvider to nil."
			)
			castDataPacket.CosmeticBulletProvider = nil
		end
	end

	local targetContainer: Instance
	if usingProvider then
		targetContainer = castDataPacket.CosmeticBulletProvider.CurrentCacheParent
	else
		targetContainer = castDataPacket.CosmeticBulletContainer
	end

	if castDataPacket.AutoIgnoreContainer == true and targetContainer ~= nil then
		local ignoreList = cast.RayInfo.Parameters.FilterDescendantsInstances
		if table.find(ignoreList, targetContainer) == nil then
			table.insert(ignoreList, targetContainer)
			cast.RayInfo.Parameters.FilterDescendantsInstances = ignoreList
		end
	end

	local event
	if RunService:IsClient() then
		event = RunService.RenderStepped
	else
		event = RunService.Heartbeat
	end

	setmetatable(cast, ActiveCastStatic)

	cast.StateInfo.UpdateConnection = event:Connect(function(delta)
		if cast.StateInfo.Paused then
			return
		end

		PrintDebug("Casting for frame.")
		local latestTrajectory = cast.StateInfo.Trajectories[#cast.StateInfo.Trajectories]
		if
			cast.StateInfo.HighFidelityBehavior == 3
			and latestTrajectory.Acceleration ~= Vector3.new()
			and cast.StateInfo.HighFidelitySegmentSize > 0
		then
			local timeAtStart = tick()

			if cast.StateInfo.IsActivelyResimulating then
				cast:Terminate()
				error(
					"Cascading cast lag encountered! The caster attempted to perform a high fidelity cast before the previous one completed, resulting in exponential cast lag. Consider increasing HighFidelitySegmentSize."
				)
			end

			cast.StateInfo.IsActivelyResimulating = true

			-- Actually want to calculate this early to find displacement
			local origin = latestTrajectory.Origin
			local totalDelta = cast.StateInfo.TotalRuntime - latestTrajectory.StartTime
			local initialVelocity = latestTrajectory.InitialVelocity
			local acceleration = latestTrajectory.Acceleration

			local lastPoint = GetPositionAtTime(totalDelta, origin, initialVelocity, acceleration)
			local lastVelocity = GetVelocityAtTime(totalDelta, initialVelocity, acceleration)
			local lastDelta = cast.StateInfo.TotalRuntime - latestTrajectory.StartTime

			cast.StateInfo.TotalRuntime += delta

			-- Recalculate this.
			totalDelta = cast.StateInfo.TotalRuntime - latestTrajectory.StartTime

			local currentPoint = GetPositionAtTime(totalDelta, origin, initialVelocity, acceleration)
			local currentVelocity = GetVelocityAtTime(totalDelta, initialVelocity, acceleration)
			local totalDisplacement = currentPoint - lastPoint -- This is the displacement from where the ray was on the last from to where the ray is now.

			local rayDir = totalDisplacement.Unit * currentVelocity.Magnitude * delta
			local targetWorldRoot = cast.RayInfo.WorldRoot
			local resultOfCast = targetWorldRoot:Raycast(lastPoint, rayDir, cast.RayInfo.Parameters)

			local point = currentPoint

			if resultOfCast ~= nil then
				point = resultOfCast.Position
			end

			local rayDisplacement = (point - lastPoint).Magnitude

			-- Now undo this. The line below in the for loop will add this time back gradually.
			cast.StateInfo.TotalRuntime -= delta

			-- And now that we have displacement, we can calculate segment size.
			local numSegmentsDecimal = rayDisplacement / cast.StateInfo.HighFidelitySegmentSize -- say rayDisplacement is 5.1, segment size is 0.5 -- 10.2 segments
			local numSegmentsReal = math.floor(numSegmentsDecimal) -- 10 segments + 0.2 extra segments
			if numSegmentsReal == 0 then
				numSegmentsReal = 1
			end

			local timeIncrement = delta / numSegmentsReal

			for segmentIndex = 1, numSegmentsReal do
				if getmetatable(cast) == nil then
					return
				end -- Could have been disposed.
				if cast.StateInfo.CancelHighResCast then
					cast.StateInfo.CancelHighResCast = false
					break
				end
				PrintDebug("[" .. segmentIndex .. "] Subcast of time increment " .. timeIncrement)
				SimulateCast(cast, timeIncrement, true)
			end

			if getmetatable(cast) == nil then
				return
			end -- Could have been disposed.
			cast.StateInfo.IsActivelyResimulating = false

			if (tick() - timeAtStart) > 0.016 * 5 then
				warn("Extreme cast lag encountered! Consider increasing HighFidelitySegmentSize.")
			end
		else
			SimulateCast(cast, delta, false)
		end
	end)

	return cast
end

function ActiveCastStatic.SetStaticFastCastReference(ref)
	FastCast = ref
end

---- GETTERS AND SETTERS ----

local function ModifyTransformation(cast: ActiveCast, velocity: Vector3?, acceleration: Vector3?, position: Vector3?)
	local trajectories = cast.StateInfo.Trajectories
	local lastTrajectory = trajectories[#trajectories]

	-- NEW BEHAVIOR: Don't create a new trajectory if we haven't even used the current one.
	if lastTrajectory.StartTime == cast.StateInfo.TotalRuntime then
		-- This trajectory is fresh out of the box. Let's just change it since it hasn't actually affected the cast yet, so changes won't have adverse effects.
		if velocity == nil then
			velocity = lastTrajectory.InitialVelocity
		end
		if acceleration == nil then
			acceleration = lastTrajectory.Acceleration
		end
		if position == nil then
			position = lastTrajectory.Origin
		end

		lastTrajectory.Origin = position
		lastTrajectory.InitialVelocity = velocity
		lastTrajectory.Acceleration = acceleration
	else
		-- The latest trajectory is done. Set its end time and get its location.
		lastTrajectory.EndTime = cast.StateInfo.TotalRuntime

		local point, velAtPoint = unpack(GetLatestTrajectoryEndInfo(cast))

		if velocity == nil then
			velocity = velAtPoint
		end
		if acceleration == nil then
			acceleration = lastTrajectory.Acceleration
		end
		if position == nil then
			position = point
		end
		table.insert(cast.StateInfo.Trajectories, {
			StartTime = cast.StateInfo.TotalRuntime,
			EndTime = -1,
			Origin = position,
			InitialVelocity = velocity,
			Acceleration = acceleration,
		})
		cast.StateInfo.CancelHighResCast = true
	end
end

function ActiveCastStatic:SetVelocity(velocity: Vector3)
	assert(getmetatable(self) == ActiveCastStatic, ERR_NOT_INSTANCE:format("SetVelocity", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)
	ModifyTransformation(self, velocity, nil, nil)
end

function ActiveCastStatic:SetAcceleration(acceleration: Vector3)
	assert(getmetatable(self) == ActiveCastStatic, ERR_NOT_INSTANCE:format("SetAcceleration", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)
	ModifyTransformation(self, nil, acceleration, nil)
end

function ActiveCastStatic:SetPosition(position: Vector3)
	assert(getmetatable(self) == ActiveCastStatic, ERR_NOT_INSTANCE:format("SetPosition", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)
	ModifyTransformation(self, nil, nil, position)
end

function ActiveCastStatic:GetVelocity(): Vector3
	assert(getmetatable(self) == ActiveCastStatic, ERR_NOT_INSTANCE:format("GetVelocity", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)
	local currentTrajectory = self.StateInfo.Trajectories[#self.StateInfo.Trajectories]
	return GetVelocityAtTime(
		self.StateInfo.TotalRuntime - currentTrajectory.StartTime,
		currentTrajectory.InitialVelocity,
		currentTrajectory.Acceleration
	)
end

function ActiveCastStatic:GetAcceleration(): Vector3
	assert(getmetatable(self) == ActiveCastStatic, ERR_NOT_INSTANCE:format("GetAcceleration", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)
	local currentTrajectory = self.StateInfo.Trajectories[#self.StateInfo.Trajectories]
	return currentTrajectory.Acceleration
end

function ActiveCastStatic:GetPosition(): Vector3
	assert(getmetatable(self) == ActiveCastStatic, ERR_NOT_INSTANCE:format("GetPosition", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)
	local currentTrajectory = self.StateInfo.Trajectories[#self.StateInfo.Trajectories]
	return GetPositionAtTime(
		self.StateInfo.TotalRuntime - currentTrajectory.StartTime,
		currentTrajectory.Origin,
		currentTrajectory.InitialVelocity,
		currentTrajectory.Acceleration
	)
end

---- ARITHMETIC ----

function ActiveCastStatic:AddVelocity(velocity: Vector3)
	assert(getmetatable(self) == ActiveCastStatic, ERR_NOT_INSTANCE:format("AddVelocity", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)
	self:SetVelocity(self:GetVelocity() + velocity)
end

function ActiveCastStatic:AddAcceleration(acceleration: Vector3)
	assert(getmetatable(self) == ActiveCastStatic, ERR_NOT_INSTANCE:format("AddAcceleration", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)
	self:SetAcceleration(self:GetAcceleration() + acceleration)
end

function ActiveCastStatic:AddPosition(position: Vector3)
	assert(getmetatable(self) == ActiveCastStatic, ERR_NOT_INSTANCE:format("AddPosition", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)
	self:SetPosition(self:GetPosition() + position)
end

---- STATE MODIFICATION ----

function ActiveCastStatic:Pause()
	assert(getmetatable(self) == ActiveCastStatic, ERR_NOT_INSTANCE:format("Pause", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)
	self.StateInfo.Paused = true
end

function ActiveCastStatic:Resume()
	assert(getmetatable(self) == ActiveCastStatic, ERR_NOT_INSTANCE:format("Resume", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)
	self.StateInfo.Paused = false
end

function ActiveCastStatic:Terminate()
	assert(getmetatable(self) == ActiveCastStatic, ERR_NOT_INSTANCE:format("Terminate", "ActiveCast.new(...)"))
	assert(self.StateInfo.UpdateConnection ~= nil, ERR_OBJECT_DISPOSED)

	-- First: Set EndTime on the latest trajectory since it is now done simulating.
	local trajectories = self.StateInfo.Trajectories
	local lastTrajectory = trajectories[#trajectories]
	lastTrajectory.EndTime = self.StateInfo.TotalRuntime

	-- Disconnect the update connection.
	self.StateInfo.UpdateConnection:Disconnect()

	-- Now fire CastTerminating
	self.Caster.CastTerminating:FireSync(self)

	-- And now set the update connection object to nil.
	self.StateInfo.UpdateConnection = nil

	-- And nuke everything in the table + clear the metatable.
	self.Caster = nil
	self.StateInfo = nil
	self.RayInfo = nil
	self.UserData = nil
	setmetatable(self, nil)
end

return ActiveCastStatic
