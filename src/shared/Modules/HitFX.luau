local Debris = game:GetService("Debris")
local config = require(script.Parent.Parent.GameConfig)

-- Impact sounds
local Glass = { "1565824613", "1565825075" }
local Metal = { "282954522", "282954538", "282954576", "1565756607", "1565756818" }
local Grass = { "1565830611", "1565831129", "1565831468", "1565832329" }
local Wood = { "287772625", "287772674", "287772718", "287772829", "287772902" }
local Concrete = { "287769261", "287769348", "287769415", "287769483", "287769538" }
local Hits = { "363818432", "363818488", "363818567", "363818611", "363818653" }
local Headshots = { "4459572527", "4459573786", "3739364168" }

local bulletHoleDecals = script.BulletHoleDecals:GetChildren()

local Effects = script

local Hitmarker = {}

function CheckColor(Color, Add)
	Color = Color + Add
	if Color > 1 then
		Color = 1
	elseif Color < 0 then
		Color = 0
	end
	return Color
end

function CreateEffect(Type, Attachment, HitPart)
	local NewType
	if Effects:FindFirstChild(Type) then
		NewType = Effects:FindFirstChild(Type)
	else
		NewType = Effects.Stone -- Default to Stone/Concrete
	end
	local NewEffect = NewType:GetChildren()[math.random(1, #NewType:GetChildren())]:Clone()
	local MaxTime = 3 -- Placeholder for max time of total effect
	for _, Effect in pairs(NewEffect:GetChildren()) do
		if not Effect:IsA("ParticleEmitter") then
			return
		end

		Effect.Parent = Attachment
		Effect.Enabled = false

		if Type == "Sand" and HitPart then
			local NewColor = HitPart.Color
			local Add = 0.3
			if HitPart.Material == Enum.Material.Fabric then
				Add = -0.2 -- Darker
			end

			NewColor = Color3.new(CheckColor(NewColor.R, Add), CheckColor(NewColor.G, Add), CheckColor(NewColor.B, Add)) -- Adjust new color

			Effect.Color = ColorSequence.new({ -- Set effect color
				ColorSequenceKeypoint.new(0, NewColor),
				ColorSequenceKeypoint.new(1, NewColor),
			})
		end

		if Effect.Rate > 10 then
			Effect:Emit(Effect.Rate / 10) -- Calculate how many particles emit based on rate
		else
			Effect:Emit(1)
		end
		if Effect.Lifetime.Max > MaxTime then
			MaxTime = Effect.Lifetime.Max
		end
	end
	local HitSound = Instance.new("Sound")
	local SoundType -- Convert Type to equivalent sound table
	if Type == "Headshot" then
		SoundType = Headshots
	elseif Type == "Hit" then
		SoundType = Hits
	elseif Type == "Glass" then
		SoundType = Glass
	elseif Type == "Metal" then
		SoundType = Metal
	elseif Type == "Ground" then
		SoundType = Grass
	elseif Type == "Wood" then
		SoundType = Wood
	elseif Type == "Stone" then
		SoundType = Concrete
	else
		SoundType = Concrete -- Default to Stone/Concrete
	end
	HitSound.Parent = Attachment
	HitSound.Volume = math.random(5, 10) / 10
	HitSound.MaxDistance = 500
	HitSound.EmitterSize = 10
	HitSound.PlaybackSpeed = math.random(34, 50) / 40
	HitSound.SoundId = "rbxassetid://" .. SoundType[math.random(1, #SoundType)]
	HitSound:Play()
	if HitSound.TimeLength > MaxTime then
		MaxTime = HitSound.TimeLength
	end
	Debris:AddItem(Attachment, MaxTime) -- Destroy attachment after all effects and sounds are done
end

function Hitmarker.HitEffect(Position, HitPart, Normal)
	--print(HitPart)
	local Material = HitPart.Material
	local Attachment = Instance.new("Attachment")
	Attachment.CFrame = CFrame.new(Position, Position + Normal)
	Attachment.Parent = workspace.Terrain
	if HitPart then
		local effectType = "Stone"

		if HitPart.Name == "Head" then
			effectType = "Headshot"
		elseif
			HitPart:IsA("BasePart")
			and (
				HitPart.Parent:FindFirstChild("Humanoid")
				or HitPart.Parent.Parent:FindFirstChild("Humanoid")
				or (HitPart.Parent.Parent.Parent and HitPart.Parent.Parent.Parent:FindFirstChild("Humanoid"))
			)
		then
			effectType = "Hit"
		elseif HitPart.Parent:IsA("Accessory") then -- Didn't feel like putting this in the other one
			effectType = "Hit"
		elseif Material == Enum.Material.Wood or Material == Enum.Material.WoodPlanks then
			effectType = "Wood"

		--elseif Material == Enum.Material.Concrete -- Stone stuff
		--	or Material == Enum.Material.Slate
		--	or Material == Enum.Material.Brick
		--	or Material == Enum.Material.Pebble
		--	or Material == Enum.Material.Cobblestone
		--	or Material == Enum.Material.Marble

		--	-- Terrain materials
		--	or Material == Enum.Material.Basalt
		--	or Material == Enum.Material.Asphalt
		--	or Material == Enum.Material.Pavement
		--	or Material == Enum.Material.Rock
		--	or Material == Enum.Material.CrackedLava
		--	or Material == Enum.Material.Sandstone
		--	or Material == Enum.Material.Limestone
		--	then

		--	CreateEffect("Stone",Attachment)
		elseif
			Material == Enum.Material.Metal -- Metals
			or Material == Enum.Material.CorrodedMetal
			or Material == Enum.Material.DiamondPlate
			or Material == Enum.Material.Neon
			-- Terrain materials
			or Material == Enum.Material.Salt
		then
			effectType = "Metal"
		elseif
			Material == Enum.Material.Grass -- Ground stuff
			-- Terrain materials
			or Material == Enum.Material.Ground
			or Material == Enum.Material.LeafyGrass
			or Material == Enum.Material.Mud
		then
			effectType = "Ground"
		elseif
			Material == Enum.Material.Sand -- Soft things
			or Material == Enum.Material.Fabric
			-- Terrain materials
			or Material == Enum.Material.Snow
		then
			effectType = "Sand"
		elseif
			Material == Enum.Material.Foil -- Brittle things
			or Material == Enum.Material.Ice
			or Material == Enum.Material.Glass
			or Material == Enum.Material.ForceField
		then
			effectType = "Glass"
		elseif HitPart.Name == "Glass" then
			effectType = "Glass"
			HitPart:Destroy()
		end

		CreateEffect(effectType, Attachment, HitPart)

		if config.bulletHoles and HitPart.Transparency < 1 then
			if
				config.glassShatter
				and (HitPart.Name == "Glass" or game.CollectionService:HasTag(HitPart, "BreakableGlass"))
			then
				return
			end
			local bulletHole = Instance.new("Part")
			bulletHole.Size = Vector3.new(0.2, 0.2, 0)
			bulletHole.Transparency = 1
			bulletHole.Anchored = false
			bulletHole.CanCollide = false
			bulletHole.CanQuery = false
			bulletHole.CanTouch = false
			bulletHole.Name = "BulletHoleTemp"
			bulletHole.CFrame = CFrame.new(Position, Position + Normal)
				* CFrame.Angles(0, 0, math.rad(math.random(360)))

			local bulletHoleDecal = bulletHoleDecals[math.random(#bulletHoleDecals)]:Clone()
			bulletHoleDecal.Parent = bulletHole

			local newWeld = Instance.new("WeldConstraint")
			newWeld.Name = "WeldToHitPart"
			newWeld.Part0 = HitPart
			newWeld.Part1 = bulletHole
			newWeld.Parent = bulletHole

			bulletHole.Parent = workspace

			Debris:AddItem(bulletHole, config.bulletHoleDespawnTime)
		end
	end
end

return Hitmarker
