--[[
	AntiCheat
	Server-side only. Drop in ServerScriptService, require it from one Script,
	call .start(). Everything else is opt-in through the public API below.

		local AntiCheat = require(game.ServerScriptService.AntiCheat)
		AntiCheat.start()

	Public API:
		AntiCheat.start()
		AntiCheat.teleport(player, cframeOrVector3)     -- teleport without a false flag
		AntiCheat.exempt(player, seconds)               -- mute movement checks
		AntiCheat.validateHit(player, info)             -- gate a damage remote
		AntiCheat.bind(remote, spec, handler)           -- rate-limited, typed remote
		AntiCheat.Remotes.t                             -- argument validators
		AntiCheat.Ownership.claim(part)                 -- pin physics to the server
		AntiCheat.Violations.onAction(action, callback)  -- hook the punishment ladder
		AntiCheat.Violations.getScore(player)
		AntiCheat.Violations.getLog(player)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(script.Config)
local Bucket = require(script.Bucket)
local History = require(script.History)
local Violations = require(script.Violations)

local Movement = require(script.Checks.Movement)
local Combat = require(script.Checks.Combat)
local Remotes = require(script.Checks.Remotes)
local Ownership = require(script.Checks.Ownership)

local AntiCheat = {
	Config = Config,
	Bucket = Bucket,
	History = History,
	Violations = Violations,
	Movement = Movement,
	Combat = Combat,
	Remotes = Remotes,
	Ownership = Ownership,
}

local started = false
local accumulator = 0

function AntiCheat.teleport(player, target)
	return Movement.teleport(player, target)
end

function AntiCheat.exempt(player, seconds)
	return Movement.exempt(player, seconds)
end

function AntiCheat.validateHit(player, info)
	return Combat.validateHit(player, info)
end

function AntiCheat.bind(remote, spec, handler)
	return Remotes.bind(remote, spec, handler)
end

function AntiCheat.start()
	assert(RunService:IsServer(), "AntiCheat is server-side only")
	if started or not Config.Enabled then
		return AntiCheat
	end
	started = true

	Violations.onAction("rubberband", function(player)
		Movement.rubberband(player)
	end)

	Ownership.start()

	local function onPlayerAdded(player)
		Movement.attach(player)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	Players.PlayerRemoving:Connect(function(player)
		Movement.detach(player)
		Combat.detach(player)
		Remotes.detach(player)
		History.clear(player)
		Violations.clear(player)
	end)

	local interval = 1 / Config.TickRate
	RunService.Heartbeat:Connect(function(deltaTime)
		accumulator += deltaTime
		if accumulator < interval then
			return
		end
		accumulator -= interval

		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				History.push(player, root.Position, now)
			end

			if Config.Movement.Enabled then
				local ok, err = pcall(Movement.tick, player, now)
				if not ok then
					warn("[AntiCheat] movement tick failed: " .. tostring(err))
				end
			end
		end
	end)

	print(string.format("[AntiCheat] started at %d Hz", Config.TickRate))
	return AntiCheat
end

return AntiCheat
