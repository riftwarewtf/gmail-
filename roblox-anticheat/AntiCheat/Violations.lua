--[[
	AntiCheat/Violations
	A decaying score per player plus a punishment ladder. Checks never punish
	directly -- they report evidence, and this module decides what it's worth.
]]

local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)

local Violations = {}

local records = {}
local handlers = {}

local function recordFor(player)
	local record = records[player]
	if not record then
		record = { score = 0, lastDecay = os.clock(), log = {}, dead = false }
		records[player] = record
	end
	return record
end

local function decay(record, now)
	local elapsed = now - record.lastDecay
	record.lastDecay = now
	record.score = math.max(0, record.score - elapsed * Config.Score.DecayPerSecond)
end

--- Register a callback for a ladder action, e.g. "rubberband", "log", "ban".
function Violations.onAction(action, callback)
	local list = handlers[action]
	if not list then
		list = {}
		handlers[action] = list
	end
	table.insert(list, callback)
	return function()
		local index = table.find(list, callback)
		if index then
			table.remove(list, index)
		end
	end
end

local function dispatch(player, action, check, record)
	if action == "log" then
		return
	end

	if Config.Studio.DisablePunishments and RunService:IsStudio() then
		print(string.format("[AntiCheat] would %s %s (score %.1f, %s)", action, player.Name, record.score, check))
		return
	end

	if action == "kick" then
		record.dead = true
		player:Kick(string.format(Config.Score.KickMessage, check))
		return
	end

	for _, callback in ipairs(handlers[action] or {}) do
		task.spawn(callback, player, check, record.score)
	end
end

--- Report evidence against a player. severity is score, not a verdict.
function Violations.report(player, check, severity, detail)
	if not player or not player.Parent then
		return
	end

	local record = recordFor(player)
	if record.dead then
		return
	end

	local now = os.clock()
	decay(record, now)
	record.score += severity

	table.insert(record.log, { at = now, check = check, severity = severity, detail = detail })
	if #record.log > 60 then
		table.remove(record.log, 1)
	end

	warn(string.format(
		"[AntiCheat] %s | %s +%d -> %.1f | %s",
		player.Name, check, severity, record.score, detail or "-"
	))

	local chosen
	for _, rung in ipairs(Config.Score.Ladder) do
		if record.score >= rung.score then
			chosen = rung
		end
	end

	if chosen then
		-- Don't re-fire a soft action every single tick.
		if chosen.action ~= "kick" then
			if now - (record.lastAction or 0) < 1 then
				return
			end
			record.lastAction = now
		end
		dispatch(player, chosen.action, check, record)
	end
end

function Violations.getScore(player)
	local record = records[player]
	if not record then
		return 0
	end
	decay(record, os.clock())
	return record.score
end

function Violations.getLog(player)
	local record = records[player]
	return record and record.log or {}
end

function Violations.clear(player)
	records[player] = nil
end

return Violations
