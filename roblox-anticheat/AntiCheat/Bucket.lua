--[[
	AntiCheat/Bucket
	Token bucket. `rate` tokens refill per second up to `burst`; :take() spends
	one. Lets a weapon fire its real burst while still capping sustained rate.
]]

local Bucket = {}
Bucket.__index = Bucket

function Bucket.new(rate, burst)
	return setmetatable({
		rate = rate,
		burst = burst,
		tokens = burst,
		last = os.clock(),
	}, Bucket)
end

function Bucket:take(amount)
	amount = amount or 1
	local now = os.clock()
	self.tokens = math.min(self.burst, self.tokens + (now - self.last) * self.rate)
	self.last = now
	if self.tokens >= amount then
		self.tokens -= amount
		return true
	end
	return false
end

return Bucket
