--[[
	ServerScriptService/Bootstrap  (Script, not ModuleScript)
	Starts the anti-cheat and shows the three integration points.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AntiCheat = require(ServerScriptService.AntiCheat)
local t = AntiCheat.Remotes.t

AntiCheat.start()

-- 1. Hook the ladder for your own reactions (logging service, soft bans, etc).
AntiCheat.Violations.onAction("rubberband", function(player, check, score)
	print(string.format("%s rubberbanded on %s at score %.1f", player.Name, check, score))
end)

-- 2. Gate every damage remote through validateHit.
local damageRemote = ReplicatedStorage:FindFirstChild("DealDamage")
if damageRemote then
	AntiCheat.bind(damageRemote, {
		name = "DealDamage",
		rate = 8,
		burst = 4,
		args = {
			t.instance("Player"),                      -- target
			t.string({ oneOf = { "pistol", "rifle", "knife" } }),
		},
	}, function(player, target, weapon)
		local ranges = { pistol = 120, rifle = 300, knife = 8 }
		local ok = AntiCheat.validateHit(player, {
			target = target,
			weapon = weapon,
			maxRange = ranges[weapon],
			shotsPerSecond = weapon == "rifle" and 10 or 4,
		})
		if not ok then
			return
		end

		local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:TakeDamage(weapon == "knife" and 55 or 25)
		end
	end)
end

-- 3. Teleport through the anti-cheat so your own code never trips the speed check.
-- AntiCheat.teleport(player, CFrame.new(0, 50, 0))
