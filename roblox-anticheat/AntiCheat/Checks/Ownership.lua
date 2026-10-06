--[[
	AntiCheat/Checks/Ownership

	Roblox hands physics ownership of nearby unanchored parts to the closest
	client, which is how fling and launch exploits work -- the exploiter owns
	the part and writes an absurd velocity to it. Tagging a part "ServerOwned"
	pins ownership to the server, and the client's writes stop replicating.

	Tag doors, vehicles, props, anything physics-driven that players touch.
]]

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Parent.Config)

local O = Config.Ownership

local Ownership = {}
local connections = {}

function Ownership.claim(instance)
	if not instance:IsA("BasePart") then
		return
	end
	-- Deferred: SetNetworkOwner throws on anchored or not-yet-parented parts.
	task.defer(function()
		if instance.Parent and not instance.Anchored then
			pcall(function()
				instance:SetNetworkOwner(nil)
			end)
		end
	end)
end

local function claimTree(instance)
	Ownership.claim(instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		Ownership.claim(descendant)
	end
end

function Ownership.start()
	if not O.Enabled then
		return
	end

	for _, instance in ipairs(CollectionService:GetTagged(O.Tag)) do
		claimTree(instance)
	end

	table.insert(connections, CollectionService:GetInstanceAddedSignal(O.Tag):Connect(claimTree))
end

function Ownership.stop()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

return Ownership
