--[[
	AntiCheat/Checks/Movement

	The client owns its own character's physics, so position is the only thing
	a speed/fly/noclip hack can't lie about -- it has to actually move the root
	part, and the server sees that. Everything here is derived from the root
	part's replicated position, never from client-reported values.

	Checks:
	  Speed   -- horizontal distance per sample vs the server's own WalkSpeed,
	             budgeted against ping so a lag spike isn't a conviction.
	  Flight  -- airborne with no floor and no downward velocity (hover), or
	             sustained upward motion that isn't a jump arc.
	  Noclip  -- root part's bounds sitting inside collidable geometry.
	  Sanity  -- NaN positions, out-of-map coordinates, fling velocities.
]]

local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Parent.Config)
local Violations = require(script.Parent.Parent.Violations)

local M = Config.Movement

local Movement = {}
local states = {}

-- States where the character is legitimately not under its own walking power.
-- Physics and Flying are deliberately absent: a client can set those itself,
-- so trusting them would hand every exploiter a free bypass. If your game uses
-- ragdolls or scripted flight, call Movement.exempt() for the duration.
local SAFE_STATES = {
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Dead] = true,
}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
rayParams.IgnoreWater = true

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.RespectCanCollide = true

local function stateFor(player)
	local state = states[player]
	if not state then
		state = { tracked = false }
		states[player] = state
	end
	return state
end

local function isCharacterPart(part)
	local model = part:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function isGrounded(character, humanoid, root)
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		return true
	end
	rayParams.FilterDescendantsInstances = { character }
	return Workspace:Raycast(root.Position, Vector3.new(0, -M.GroundProbe, 0), rayParams) ~= nil
end

--- Returns the offending part if the root part is buried in collidable world
--- geometry. Shrunk to 60% so brushing a wall never counts.
local function insideGeometry(character, root)
	overlapParams.FilterDescendantsInstances = { character }
	local probe = root.Size * 0.6
	for _, part in ipairs(Workspace:GetPartBoundsInBox(root.CFrame, probe, overlapParams)) do
		if part:IsA("BasePart") and part.CanCollide and not isCharacterPart(part) then
			return part
		end
	end
	return nil
end

function Movement.attach(player)
	local state = stateFor(player)

	local function onCharacter(character)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if not root then
			return
		end
		state.tracked = true
		state.lastPosition = root.Position
		state.safePosition = root.Position
		state.lastSampleAt = os.clock()
		state.graceUntil = os.clock() + M.SpawnGrace
		state.speedTicks, state.hoverTicks, state.riseTicks, state.noclipTicks = 0, 0, 0, 0
	end

	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	state.connection = player.CharacterAdded:Connect(onCharacter)
end

function Movement.detach(player)
	local state = states[player]
	if state and state.connection then
		state.connection:Disconnect()
	end
	states[player] = nil
end

--- Mute movement checks for this player (scripted launches, ragdolls, cutscenes).
function Movement.exempt(player, duration)
	local state = stateFor(player)
	state.graceUntil = math.max(state.graceUntil or 0, os.clock() + (duration or M.TeleportGrace))
end

--- Move a player without tripping the speed check. Use this for every
--- server-side teleport in your game instead of setting CFrame directly.
function Movement.teleport(player, target)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	root.CFrame = typeof(target) == "CFrame" and target or CFrame.new(target)
	local state = stateFor(player)
	state.lastPosition = root.Position
	state.safePosition = root.Position
	Movement.exempt(player, M.TeleportGrace)
	return true
end

--- Yank the player back to their last known-good grounded position.
function Movement.rubberband(player)
	local state = states[player]
	if not state or not state.safePosition then
		return
	end
	Movement.teleport(player, state.safePosition)
end

function Movement.tick(player, now)
	local state = states[player]
	if not state or not state.tracked then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end

	local position = root.Position
	local last = state.lastPosition or position
	local delta = now - (state.lastSampleAt or now)
	state.lastSampleAt = now

	-- Sanity first: NaN coordinates and fling velocities are corrected
	-- immediately regardless of score, because they break the server too.
	local velocity = root.AssemblyLinearVelocity
	local notFinite = position.X ~= position.X or position.Y ~= position.Y or position.Z ~= position.Z
		or velocity.Magnitude ~= velocity.Magnitude
	local offMap = math.abs(position.X) > M.MaxCoordinate
		or math.abs(position.Y) > M.MaxCoordinate
		or math.abs(position.Z) > M.MaxCoordinate
	local flung = velocity.Magnitude > M.MaxVelocity

	if notFinite or offMap or flung then
		Violations.report(player, "Movement/Sanity", M.SanitySeverity, string.format(
			"finite=%s offMap=%s vel=%.0f", tostring(not notFinite), tostring(offMap), flung and velocity.Magnitude or 0
		))
		Movement.teleport(player, state.safePosition or last)
		return
	end

	if delta <= 0 or delta > M.MaxTickDelta or now < (state.graceUntil or 0) then
		state.lastPosition = position
		return
	end

	-- Noclip is state-independent: being inside a wall is never legitimate,
	-- seated or not, so this runs before the SAFE_STATES bail-out.
	local movedEnough = (position - last).Magnitude > 0.05
	local inside = insideGeometry(character, root)
	if inside then
		local crossed = nil
		if movedEnough then
			rayParams.FilterDescendantsInstances = { character }
			local result = Workspace:Raycast(last, position - last, rayParams)
			if result and result.Instance.CanCollide and not isCharacterPart(result.Instance) then
				crossed = result.Instance
			end
		end
		state.noclipTicks += (crossed and 2 or 1)
		if state.noclipTicks >= M.NoclipTicksToFlag then
			state.noclipTicks = 0
			Violations.report(player, "Movement/Noclip", M.NoclipSeverity, "inside " .. inside:GetFullName())
		end
	else
		state.noclipTicks = 0
	end

	local humanoidState = humanoid:GetState()
	if SAFE_STATES[humanoidState] or humanoid.SeatPart then
		state.lastPosition = position
		state.safePosition = position
		state.speedTicks, state.hoverTicks, state.riseTicks = 0, 0, 0
		return
	end

	-- Travel budget: the time slice plus however stale this player's
	-- replication is. Without the ping term, 200ms players get kicked.
	local ping = math.clamp(player:GetNetworkPing(), 0, 0.5)
	local window = delta + ping + M.LagAllowance

	local offset = position - last
	local horizontal = Vector3.new(offset.X, 0, offset.Z).Magnitude
	local allowed = (humanoid.WalkSpeed * M.SpeedTolerance + M.SpeedBuffer) * window

	if horizontal > allowed then
		state.speedTicks += 1
		if state.speedTicks >= M.SpeedTicksToFlag then
			state.speedTicks = 0
			Violations.report(player, "Movement/Speed", M.SpeedSeverity, string.format(
				"%.1f studs in %.2fs, budget %.1f (WalkSpeed %.0f)", horizontal, window, allowed, humanoid.WalkSpeed
			))
		end
	else
		state.speedTicks = math.max(0, state.speedTicks - 1)
	end

	local grounded = isGrounded(character, humanoid, root)
	local vertical = offset.Y / delta

	if grounded then
		state.hoverTicks, state.riseTicks = 0, 0
	else
		if math.abs(vertical) < M.HoverVelocity then
			state.hoverTicks += 1
		else
			state.hoverTicks = 0
		end

		if vertical > M.MaxRiseSpeed then
			state.riseTicks += 1
		else
			state.riseTicks = math.max(0, state.riseTicks - 1)
		end
	end

	if state.hoverTicks >= M.HoverTicksToFlag or state.riseTicks >= M.RiseTicksToFlag then
		local reason = state.hoverTicks >= M.HoverTicksToFlag and "hovering" or "rising"
		state.hoverTicks, state.riseTicks = 0, 0
		Violations.report(player, "Movement/Flight", M.FlightSeverity, string.format(
			"%s, vertical %.1f studs/s, no floor", reason, vertical
		))
	end

	if grounded and state.speedTicks == 0 and state.hoverTicks == 0 and state.noclipTicks == 0 then
		state.safePosition = position
	end

	state.lastPosition = position
end

return Movement
