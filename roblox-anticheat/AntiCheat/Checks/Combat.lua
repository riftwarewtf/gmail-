--[[
	AntiCheat/Checks/Combat

	A client telling the server "I hit this guy" is a request, not a fact.
	validateHit() answers three questions the client can't fake: could they
	fire that fast, were they close enough, and was anything in the way --
	with the target rewound to where the shooter saw them, so lag isn't a crime.

	Call it from the server handler of every damage remote. If it returns
	false, drop the hit; the score ladder handles the repeat offenders.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Parent.Config)
local Violations = require(script.Parent.Parent.Violations)
local History = require(script.Parent.Parent.History)
local Bucket = require(script.Parent.Parent.Bucket)

local C = Config.Combat

local Combat = {}
local buckets = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
rayParams.IgnoreWater = true

local function bucketFor(player, weapon, rate, burst)
	local byWeapon = buckets[player]
	if not byWeapon then
		byWeapon = {}
		buckets[player] = byWeapon
	end
	local bucket = byWeapon[weapon]
	if not bucket then
		bucket = Bucket.new(rate, burst)
		byWeapon[weapon] = bucket
	end
	return bucket
end

function Combat.detach(player)
	buckets[player] = nil
end

--[[
	info = {
		target = Player | Model,        -- required
		weapon = "shotgun",             -- rate limiting is per weapon key
		maxRange = 18,                  -- studs; defaults to Config
		shotsPerSecond = 6,
		burst = 3,
		requireLineOfSight = true,      -- false for explosives / melee sweeps
	}

	returns ok: boolean, reason: string?
]]
function Combat.validateHit(player, info)
	if not C.Enabled then
		return true
	end

	info = info or {}
	local weapon = info.weapon or "default"
	local rate = info.shotsPerSecond or C.DefaultShotsPerSecond
	local burst = info.burst or C.DefaultBurst

	if not bucketFor(player, weapon, rate, burst):take() then
		Violations.report(player, "Combat/FireRate", C.RateSeverity, string.format(
			"%s exceeded %.1f/s", weapon, rate
		))
		return false, "rate"
	end

	local character = player.Character
	local origin = character and character:FindFirstChild("HumanoidRootPart")
	if not origin then
		return false, "no-character"
	end

	local targetCharacter = info.target
	if targetCharacter and targetCharacter:IsA("Player") then
		targetCharacter = targetCharacter.Character
	end
	if not targetCharacter then
		return false, "no-target"
	end

	local targetHumanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
	if not targetHumanoid or targetHumanoid.Health <= 0 then
		return false, "dead-target"
	end

	local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
	local targetPosition = targetRoot and targetRoot.Position
	local ping = math.clamp(player:GetNetworkPing(), 0, 0.5)

	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	if targetPlayer then
		targetPosition = History.rewind(targetPlayer, os.clock() - ping) or targetPosition
	end
	if not targetPosition then
		return false, "no-target"
	end

	local maxRange = info.maxRange or C.DefaultMaxRange
	local distance = (targetPosition - origin.Position).Magnitude
	if distance > maxRange + C.RangeTolerance then
		Violations.report(player, "Combat/Range", C.RangeSeverity, string.format(
			"%s hit at %.1f studs, max %.1f", weapon, distance, maxRange
		))
		return false, "range"
	end

	local needsSight = C.RequireLineOfSight and info.requireLineOfSight ~= false
	if needsSight then
		rayParams.FilterDescendantsInstances = { character, targetCharacter }
		local blocked = Workspace:Raycast(origin.Position, targetPosition - origin.Position, rayParams)
		if blocked then
			Violations.report(player, "Combat/LineOfSight", C.SightSeverity, string.format(
				"%s blocked by %s", weapon, blocked.Instance:GetFullName()
			))
			return false, "line-of-sight"
		end
	end

	return true
end

return Combat
