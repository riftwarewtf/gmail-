--[[
	AntiCheat/Checks/Remotes

	Remotes are the only door a client has into your server, so every one of
	them gets a rate limit and an argument schema. Bind through Remotes.bind()
	instead of OnServerEvent and malformed or flooded calls never reach your
	handler -- they land in the violation ledger instead.

		local t = AntiCheat.Remotes.t
		AntiCheat.Remotes.bind(buyItem, {
			name = "BuyItem",
			rate = 4, burst = 6,
			args = { t.string({ maxLength = 32, pattern = "^%w+$" }) },
		}, function(player, itemId) ... end)
]]

local Config = require(script.Parent.Parent.Config)
local Violations = require(script.Parent.Parent.Violations)
local Bucket = require(script.Parent.Parent.Bucket)

local R = Config.Remotes

local Remotes = {}
local buckets = {}

-- Validators ---------------------------------------------------------------

local t = {}
Remotes.t = t

local function isFinite(value)
	return value == value and value ~= math.huge and value ~= -math.huge
end

function t.any()
	return function()
		return true
	end
end

function t.boolean()
	return function(value)
		return type(value) == "boolean"
	end
end

function t.number(opts)
	opts = opts or {}
	return function(value)
		if type(value) ~= "number" or not isFinite(value) then
			return false
		end
		if opts.min and value < opts.min then
			return false
		end
		if opts.max and value > opts.max then
			return false
		end
		return true
	end
end

function t.integer(opts)
	local inner = t.number(opts)
	return function(value)
		return inner(value) and value % 1 == 0
	end
end

function t.string(opts)
	opts = opts or {}
	return function(value)
		if type(value) ~= "string" then
			return false
		end
		if opts.maxLength and #value > opts.maxLength then
			return false
		end
		if opts.minLength and #value < opts.minLength then
			return false
		end
		if opts.pattern and not string.match(value, opts.pattern) then
			return false
		end
		if opts.oneOf then
			return table.find(opts.oneOf, value) ~= nil
		end
		return true
	end
end

function t.vector3(opts)
	opts = opts or {}
	return function(value)
		if typeof(value) ~= "Vector3" then
			return false
		end
		if not (isFinite(value.X) and isFinite(value.Y) and isFinite(value.Z)) then
			return false
		end
		if opts.maxMagnitude and value.Magnitude > opts.maxMagnitude then
			return false
		end
		return true
	end
end

--- Instances are the classic exploit vector: always pin the class, and pin
--- the ancestor too so a client can't hand you something out of its own camera.
function t.instance(className, opts)
	opts = opts or {}
	return function(value)
		if typeof(value) ~= "Instance" or not value:IsA(className) then
			return false
		end
		if opts.ancestor and not value:IsDescendantOf(opts.ancestor) then
			return false
		end
		return true
	end
end

function t.optional(inner)
	return function(value)
		return value == nil or inner(value)
	end
end

function t.listOf(inner, maxCount)
	return function(value)
		if type(value) ~= "table" then
			return false
		end
		local count = 0
		for key, item in pairs(value) do
			if type(key) ~= "number" or key % 1 ~= 0 then
				return false
			end
			if not inner(item) then
				return false
			end
			count += 1
			if maxCount and count > maxCount then
				return false
			end
		end
		return true
	end
end

-- Binding ------------------------------------------------------------------

local function allow(player, name, rate, burst, args, ...)
	if not R.Enabled then
		return true
	end

	local byRemote = buckets[player]
	if not byRemote then
		byRemote = {}
		buckets[player] = byRemote
	end
	local bucket = byRemote[name]
	if not bucket then
		bucket = Bucket.new(rate, burst)
		byRemote[name] = bucket
	end

	if not bucket:take() then
		Violations.report(player, "Remote/Rate", R.RateSeverity, string.format("%s flooded (%.1f/s)", name, rate))
		return false
	end

	if args then
		local count = select("#", ...)
		if count > #args then
			Violations.report(player, "Remote/Schema", R.SchemaSeverity, string.format(
				"%s got %d args, expected %d", name, count, #args
			))
			return false
		end
		for index = 1, #args do
			local value = select(index, ...)
			if not args[index](value) then
				Violations.report(player, "Remote/Schema", R.SchemaSeverity, string.format(
					"%s arg #%d invalid (%s)", name, index, typeof(value)
				))
				return false
			end
		end
	end

	return true
end

function Remotes.bind(remote, spec, handler)
	spec = spec or {}
	local name = spec.name or remote.Name
	local rate = spec.rate or R.DefaultRate
	local burst = spec.burst or R.DefaultBurst
	local args = spec.args

	if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
		return remote.OnServerEvent:Connect(function(player, ...)
			if not allow(player, name, rate, burst, args, ...) then
				return
			end
			local ok, err = pcall(handler, player, ...)
			if not ok then
				warn(string.format("[AntiCheat] handler error on %s: %s", name, tostring(err)))
			end
		end)
	elseif remote:IsA("RemoteFunction") then
		remote.OnServerInvoke = function(player, ...)
			if not allow(player, name, rate, burst, args, ...) then
				return nil
			end
			return handler(player, ...)
		end
		return remote
	end

	error("Remotes.bind expects a RemoteEvent, UnreliableRemoteEvent or RemoteFunction", 2)
end

function Remotes.detach(player)
	buckets[player] = nil
end

return Remotes
