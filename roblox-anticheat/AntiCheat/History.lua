--[[
	AntiCheat/History
	Rolling position buffer per player. Combat checks rewind a target to where
	the shooter actually saw them (now - ping) instead of where they are now,
	so high-ping players stop getting flagged for legitimate hits.
]]

local Config = require(script.Parent.Config)

local History = {}
local buffers = {}

function History.push(player, position, now)
	local buffer = buffers[player]
	if not buffer then
		buffer = {}
		buffers[player] = buffer
	end

	table.insert(buffer, { t = now, p = position })

	local cutoff = now - Config.History.Seconds
	while #buffer > 0 and buffer[1].t < cutoff do
		table.remove(buffer, 1)
	end
end

--- Position at `timestamp`, interpolated between the two nearest samples.
function History.rewind(player, timestamp)
	local buffer = buffers[player]
	if not buffer or #buffer == 0 then
		return nil
	end
	if timestamp >= buffer[#buffer].t then
		return buffer[#buffer].p
	end
	if timestamp <= buffer[1].t then
		return buffer[1].p
	end

	for index = 1, #buffer - 1 do
		local a, b = buffer[index], buffer[index + 1]
		if timestamp >= a.t and timestamp <= b.t then
			local span = b.t - a.t
			local alpha = span > 0 and (timestamp - a.t) / span or 0
			return a.p:Lerp(b.p, alpha)
		end
	end

	return buffer[#buffer].p
end

function History.clear(player)
	buffers[player] = nil
end

return History
