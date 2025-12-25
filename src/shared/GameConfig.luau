-- Main game settings

local config = {}

-- Game settings

config.thirdPersonFiring = true -- Allow the player to fire from third person (unfinished)
config.arcadeBullets = false -- Gives bullets a faint streak similar to FE Gun Kit, looks pretty bad with tracers enabled

config.leaderboard = true -- Creates a simple kill death leaderboard
config.rblxDamageTags = true -- Include Roblox built in damage tags when counting kills

config.systemChat = true -- Sends messages in chat when players join, leave, and die
config.deathScreen = true -- Displays a screen after death with a respawn counter

config.fallDamage = true -- Should there be fall damage?
config.fallDamageDist = 19 -- Minimum distance to take damage
config.fallDamageMultiplier = 0.7

config.teamKill = true
config.teamTracers = false

config.firstPersonBody = true -- Should the player's body be visible in first person?
config.headRotation = false -- Should the head rotate when in third person
config.headRotationSpeed = 15
config.disableHeadRotation = false -- Disables head rotation entirely for both first and third person (Your viewmodel will still move up and down)
config.headRotationEventRate = 0.1 -- How often should head rotation be replicated
config.replicatedHeadRotationSpeed = 0.6 -- How quickly should other player's head's be rotated

config.useDeathCameraSubject = true -- If this is true, your camera will follow your corpse when you die

config.explosionRaycast = true -- Check with a raycast if players should be damaged

config.lockFirstPerson = false -- Can the player exit first person with a gun equipped?
-- DO NOT enable this setting if you want players to always be locked to first person
-- To do that, go to StarterPlayer and change the default CameraMode

config.speedOfSound = true -- Firing sounds are delayed based on distance to the player.
config.meterMultiplier = 3.5 -- Allows you to manually decide how many meters are in a stud, used for muzzle velocity and the speed of sound.

-- Gun dropping settings

config.gunDropping = true
config.dropOnDeath = true
config.dropOnLeave = true
config.dropDespawnTime = 60 -- How long should guns stay on the ground?
config.maxDroppedGuns = 15 -- How many can be on the ground at once?
config.pickupDistance = 7
config.dropGunAnchorTime = 3 -- Anchor dropped gun models after this amount of time

config.canReloadWhileAiming = false -- Can the player reload while aiming?

-- Movement settings

config.walkSpeed = 10
config.sprintSpeed = 16
config.crouchSpeed = 6
config.proneSpeed = 3
config.strafeSpeedMultiplier = 0.6 -- Movement speed is multiplied by this while strafing or moving backwards. Set this to 1 if you don't want a movement reduction while strafing.
config.canSprintWhileStrafing = true -- Can the player sprint while not moving forwards?
-- If other scripts are conflicting with SPH's movement, you can override them using the attributes under the CharacterMovement script.

config.movementLeaning = true -- Will players lean into the direction they're moving? (This setting can cause issues if other scripts are trying to animate the torso)
config.replicateMovementLeaning = true -- Replicate other players leaning?
config.maxLeanAngle = 5 -- How far can players lean while moving

config.stanceChangeTime = 0.3 -- How long it takes to transition between stances

config.canLean = true -- Can the player lean around corners
config.canCrouch = true -- Can the player crouch
config.canProne = true -- Can the player go prone (This setting doesn't matter if canCrouch is false)
config.proneAngle = true -- Adjust prone angle based on ground

config.jumpCooldown = 2 -- Time between jumps

config.useHigherAnimPriority = true -- Uses higher animation priorities for the Crouch and Prone animations to avoid conflicting with the default tool idle animation.
config.firstPersonAimAnim = false -- Should aim animations play in first person?
config.proceduralAimAnim = true -- Used only in first person.

-- Input settings

-- To disable a keybind, set it to nil
-- config.example = {nil}
-- To add an alternate input, add another item to the table
-- config.example = {input1, input2, input3}

config.keySprint = { Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3 }
config.keyReload = { Enum.KeyCode.R, Enum.KeyCode.ButtonX }
config.keyChamber = { Enum.KeyCode.F }
config.sightSwitch = { Enum.KeyCode.T }
config.freeLook = { Enum.UserInputType.MouseButton3 }
config.lowerStance = { Enum.KeyCode.C }
config.raiseStance = { Enum.KeyCode.X }
config.holdUp = { Enum.KeyCode.B }
config.holdPatrol = { Enum.KeyCode.N }
config.holdDown = { Enum.KeyCode.M }
config.switchFireMode = { Enum.KeyCode.V }
config.leanLeft = { Enum.KeyCode.Q }
config.leanRight = { Enum.KeyCode.E }
config.dropKey = { Enum.KeyCode.Backspace, Enum.KeyCode.ButtonB }
config.pickupKey = { Enum.KeyCode.G }
config.toggleLaser = { Enum.KeyCode.J }
config.toggleFlashlight = { Enum.KeyCode.H }
config.holdForScrollZoom = Enum.KeyCode.LeftControl
config.fireGun = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 }
config.aimGun = { Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2 }
config.toggleSuppressor = { Enum.KeyCode.Y } -- Unfinished
config.toggleBipod = { Enum.KeyCode.Z }

config.defaultAimSensitivity = 0.4 -- Scrolling up and down while aiming will increase/decrease your aim sensitivity
config.gunInputPriority = 100 -- Priority level for gun inputs
config.movementInputPriority = 100 -- Priority level for movement inputs

config.mobileButtons = true -- Adds mobile buttons on screen if using a touchscreen device
config.toggleAiming = false -- Switches all players to using toggle aim instead of hold to aim

-- Performance settings

config.animDistance = 1000 -- Maximum distance to see a player's animations
config.fireEffectDistance = 4000 -- Maximum distance for firing effects to be replicated
config.maxBulletDistance = 6000 -- Bullets that fly further than this distance will be deleted
config.maxHitDistance = 1000 -- Maximum distance to see bullet hit effects

config.ragdolls = true -- Should players ragdoll on death?
config.bodyDespawn = 60 -- Bodies are removed after this time
config.bodyLimit = 15 -- Maximum number of bodies
config.bodyAnchorTime = 10 -- Corpse is anchored and uncollided after this amount of time

config.shellEjection = true -- Game-wide override for shell ejection
config.shellDistance = 50 -- Shells won't be ejected beyond this distance
config.shellMaxCount = 30 -- Maximum that can be on the ground at once
config.shellDespawn = 10 -- Shells are auto deleted after this amount of time
config.shellAnchorTime = 3 -- Shells are anchored after this amount of time

config.firstPersonHolsters = false -- Should holsters be shown in first person? (Very laggy if you have too many holsters at once)
config.blurEffects = false -- Experimental stuff with depth of field

config.despawnEmptyAmmoBoxes = true -- Should empty ammo boxes be destroyed after some time?
config.ammoBoxDespawnTime = 10

config.maxBullets = 300 -- Maximum number of bullets that are cached (Cache size will temporarily increase if this is exceeded)

config.bulletHoles = true
config.bulletHoleDespawnTime = 20

config.glassShatter = true -- Should glass shatter when shot? (Must be named "Glass" or given tag "BreakableGlass")
config.glassShardDespawnTime = 30 -- How long should shards stay on the ground?
config.glassRespawnTime = 120 -- How long until glass is replaced?

-- Physics settings

config.bulletAcceleration = Vector3.new(0, -workspace.Gravity, 0) -- This is used for the bullet drop force
config.useBulletForce = true -- Should bullet impacts be able to push things around?
config.bulletPen = true -- Can bullets pierce objects?

-- Viewmodel settings

config.breathingSpeed = 7 -- Speed of the breathing cycle
config.breathingDist = 0.01 -- Distance the viewmodel will move while breathing
config.breathingAimMultiplier = 0.17 -- Breathing dist is multiplied by this when aiming, the closer this number is to 1 the more breathing there is

config.bobSpeed = 10 -- How quickly the viewmodel should move back and forth, this is scaled based on walk speed
config.bobDampening = 10 -- Higher number = less bobbing
config.aimBobDampening = 1.5 -- Higher number = less bobbing while aiming
config.cameraMovement = false -- Should the camera bob around?
config.cameraBobDampening = 1 -- Higher number = less bobbing
config.cameraTilting = false -- Should the camera tilt when looking and moving around?
config.cameraLimitInSeats = true -- Limit camera angle to 180 degrees when sitting in a seat (Disabling this may cause issues with other camera settings)
config.canEquipInVehicleSeat = false -- Can the player equip guns while using a vehicle? (Setting this to true may cause input overlaps.)

config.hipfireMove = true -- Allows you to move your gun off center while hip firing
config.hipfireMoveX = 15 -- Max angle that the gun can move horizontally
config.hipfireMoveY = 10 -- Max angle that the gun can move vertically
config.hipfireMoveSpeed = 0.05
config.offCenterAiming = false -- Allow the player to move off center while aiming

config.pushBackViewmodel = true -- Should the gun move back when getting close to a wall?
config.raiseGunAtWall = true -- Should the gun be raised when too close to a wall?

config.fireWithFreelook = false -- Can the player fire their gun while freelook is active?

config.maxStrafeRoll = 20 -- How much the viewmodel can lean left and right when strafing

config.showAccessoriesFP = true -- Should accessories be shown in first person?

-- Effects settings

config.lowHealthEffects = true -- Low health visual effects, reduced movement speed, and shaking when aiming
config.damageFlinching = true -- Camera gets knocked off center when taking damage
config.suppressionEffects = true -- Tunnel vision and crack sounds
config.footstepSounds = true -- Replaces the default walk sound with material based sounds

config.tracerStartDistance = 15 -- Tracers and arcade bullets don't appear until they're this distance away from you
config.fireSoundVariation = 500 -- Lowering this number increases the variation in pitch (playback speed) of fire and echo sounds

config.firstPersonEcho = true -- If this is set to false other players will hear echo sounds, but not yourself

config.laserTrail = true -- Should lasers have a trail

-- Destruction settings

config.destructibleObjects = true
config.destructibleDespawnTime = 30
config.disablePlayerDebrisCollision = true -- Stops players from colliding with debris from destroyed objects.

-- Anti Exploit settings

config.printKillLogs = true -- Prints a message in output when a player kills another.
config.serverSideHitCheck = false -- Uses a server-side raycast to check if a shot was possible.
config.listenForKillAll = true -- Kicks players that attempt to kill multiple players at once.
config.multiKillThreshold = 2 -- Trying to kill more than this number of players at once will kick the player (If the setting above is enabled).
config.antiFreecam = true -- Prevent players from firing shots if their camera is too far away.
config.requireEquippedGun = true -- Guns cannot deal damage if not currently equipped.
config.listenForReloadSpam = true -- Adds cooldown for how often the reload event can be fired.
config.listenForExplosionSpam = true -- Kicks players that attempt to call bulletHit with explosions too frequently.
config.killAngleCheck = false -- Prevents players from killing enemies that aren't being looked at.

--config.ammoCountCheck = false -- Prevents players from firing the bulletHit event without firing a gun
--config.multiKillDistanceCheck = false -- Tries to pevent players from killing multiple players that are far away from each other (Requires listenForKillAll)
--config.strikes = false -- Attempt to use events suspiciously will add a "strike" to a player
--config.maxStrike = 3 -- If a player reaches this number of strikes, they will be kicked from the game
--config.serverBanList = false -- If a player is kicked by SPH for exploiting, they will also be banned from this server

-- Version

config.version = "v1.3.0" -- Used only for debugging and analytics

return config -- DO NOT try to add new or custom settings after this line!
