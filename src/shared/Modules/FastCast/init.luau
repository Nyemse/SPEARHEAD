--!nocheck
-- ^ change to strict to crash studio c:

--[[
	Written by Eti the Spirit (18406183)
	
		The latest patch notes can be located here (and do note, the version at the top of this script might be outdated. I have a thing for forgetting to change it):
		>	https://etithespirit.github.io/FastCastAPIDocs/changelog
		
		*** If anything is broken, please don't hesitate to message me! ***
		
		YOU CAN FIND IMPORTANT USAGE INFORMATION HERE: https://etithespirit.github.io/FastCastAPIDocs
		YOU CAN FIND IMPORTANT USAGE INFORMATION HERE: https://etithespirit.github.io/FastCastAPIDocs
		YOU CAN FIND IMPORTANT USAGE INFORMATION HERE: https://etithespirit.github.io/FastCastAPIDocs
		
		YOU SHOULD ONLY CREATE ONE CASTER PER GUN.
		YOU SHOULD >>>NEVER<<< CREATE A NEW CASTER EVERY TIME THE GUN NEEDS TO BE FIRED.
		
		A caster (created with FastCast.new()) represents a "gun".
		When you consider a gun, you think of stats like accuracy, bullet speed, etc. This is the info a caster stores. 
	
	--
	
	This is a library used to create hitscan-based guns that simulate projectile physics.
	
	This means:
		- You don't have to worry about bullet lag / jittering
		- You don't have to worry about keeping bullets at a low speed due to physics being finnicky between clients
		- You don't have to worry about misfires in bullet's Touched event (e.g. where it may going so fast that it doesn't register)
		
	Hitscan-based guns are commonly seen in the form of laser beams, among other things. Hitscan simply raycasts out to a target
	and says whether it hit or not.
	
	Unfortunately, while reliable in terms of saying if something got hit or not, this method alone cannot be used if you wish
	to implement bullet travel time into a weapon. As a result of that, I made this library - an excellent remedy to this dilemma.
	
	FastCast is intended to be require()'d once in a script, as you can create as many casters as you need with FastCast.new()
	This is generally handy since you can store settings and information in these casters, and even send them out to other scripts via events
	for use.
	
	Remember -- A "Caster" represents an entire gun (or whatever is launching your projectiles), *NOT* the individual bullets.
	Make the caster once, then use the caster to fire your bullets. Do not make a caster for each bullet.
--]]

-----------------------------------------------------------
-------------------- MODULE DEFINITION --------------------
-----------------------------------------------------------

local FastCast = {}
FastCast.DebugLogging = false
FastCast.VisualizeCasts = false
FastCast.__index = FastCast
FastCast.__type = "FastCast" -- For compatibility with TypeMarshaller

-- Extra stuff
FastCast.HighFidelityBehavior = {
	Default = 1,
	Always = 3,
}

-----------------------------------------------------------
----------------------- STATIC DATA -----------------------
-----------------------------------------------------------
local ActiveCastStatic = require(script.ActiveCast)
local Signal = require(script.Signal)
local table = require(script.Table)

-- Format params: methodName, ctorName
local ERR_NOT_INSTANCE =
	"Cannot statically invoke method '%s' - It is an instance method. Call it on an instance of this class created via %s"

-- Format params: paramName, expectedType, actualType
local ERR_INVALID_TYPE = "Invalid type for parameter '%s' (Expected %s, got %s)"

-- The name of the folder containing the 3D GUI elements for visualizing casts.
local FC_VIS_OBJ_NAME = "FastCastVisualizationObjects"

-- Format params: N/A
local ERR_OBJECT_DISPOSED = "This Caster has been disposed. It can no longer be used."

-----------------------------------------------------------
--------------------- TYPE DEFINITION ---------------------
-----------------------------------------------------------

-- This will inject all types into this context.
local TypeDefs = require(script.TypeDefinitions)
type CanPierceFunction = TypeDefs.CanPierceFunction
type GenericTable = TypeDefs.GenericTable
type Caster = TypeDefs.Caster
type FastCastBehavior = TypeDefs.FastCastBehavior
type CastTrajectory = TypeDefs.CastTrajectory
type CastStateInfo = TypeDefs.CastStateInfo
type CastRayInfo = TypeDefs.CastRayInfo
type ActiveCast = TypeDefs.ActiveCast

-----------------------------------------------------------
----------------------- STATIC CODE -----------------------
-----------------------------------------------------------

-- Tell the ActiveCast factory module what FastCast actually *is*.
ActiveCastStatic.SetStaticFastCastReference(FastCast)

-----------------------------------------------------------
------------------------- EXPORTS -------------------------
-----------------------------------------------------------

-- Constructor.
function FastCast.new()
	return setmetatable({
		LengthChanged = Signal.new("LengthChanged"),
		RayHit = Signal.new("RayHit"),
		RayPierced = Signal.new("RayPierced"),
		CastTerminating = Signal.new("CastTerminating"),
		WorldRoot = workspace,
	}, FastCast)
end

-- Create a new ray info object.
-- This is just a utility alias with some extra type checking.
function FastCast.newBehavior(): FastCastBehavior
	-- raycastParams, maxDistance, acceleration, canPierceFunction, cosmeticBulletTemplate, cosmeticBulletContainer, autoIgnoreBulletContainer
	return {
		RaycastParams = nil,
		Acceleration = Vector3.new(),
		MaxDistance = 1000,
		CanPierceFunction = nil,
		HighFidelityBehavior = FastCast.HighFidelityBehavior.Default,
		HighFidelitySegmentSize = 0.5,
		CosmeticBulletTemplate = nil,
		CosmeticBulletProvider = nil,
		CosmeticBulletContainer = nil,
		AutoIgnoreContainer = true,
	}
end

local DEFAULT_DATA_PACKET = FastCast.newBehavior()
function FastCast:Fire(
	origin: Vector3,
	direction: Vector3,
	velocity: Vector3 | number,
	castDataPacket: FastCastBehavior?
): ActiveCast
	if castDataPacket == nil then
		castDataPacket = DEFAULT_DATA_PACKET
	end

	local cast = ActiveCastStatic.new(self, origin, direction, velocity, castDataPacket)
	cast.RayInfo.WorldRoot = self.WorldRoot
	return cast
end

-- Export
return FastCast
