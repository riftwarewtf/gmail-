--[[
	AntiCheat/Config
	Every number the system reasons about lives here. Tune these to your game
	before you tune anything else -- most false positives are a config problem.
]]

return {
	Enabled = true,

	-- How many times per second every player is sampled. 10 is a good balance:
	-- fast enough to catch a 2x speed hack, cheap enough for a 50-player server.
	TickRate = 10,

	Studio = {
		-- In Studio, log everything but never kick/rubberband yourself.
		DisablePunishments = true,
	},

	Score = {
		-- Violation score bleeds off over time so one bad lag spike never
		-- accumulates into a kick across a whole session.
		DecayPerSecond = 1.5,

		-- Rungs are evaluated low -> high; the highest one reached fires.
		Ladder = {
			{ score = 15, action = "log" },
			{ score = 35, action = "rubberband" },
			{ score = 70, action = "kick" },
		},

		KickMessage = "Disconnected by anti-cheat. (%s)",
	},

	Movement = {
		Enabled = true,

		SpawnGrace = 3,          -- seconds after spawn with checks muted
		TeleportGrace = 1.5,     -- seconds muted after a server-side teleport
		MaxTickDelta = 0.75,     -- skip samples longer than this (server hitch)
		LagAllowance = 0.15,     -- extra seconds of travel budget on top of ping

		SpeedTolerance = 1.35,   -- multiplier on the server's view of WalkSpeed
		SpeedBuffer = 4,         -- flat studs/s of slack (slopes, knockback)
		SpeedTicksToFlag = 3,
		SpeedSeverity = 6,

		HoverVelocity = 2.5,     -- |vertical studs/s| counted as "hovering"
		HoverTicksToFlag = 8,    -- ~0.8s airborne and not falling
		MaxRiseSpeed = 60,       -- sustained upward studs/s that isn't a jump
		RiseTicksToFlag = 4,
		GroundProbe = 6,         -- downward raycast length for the ground test
		FlightSeverity = 10,

		NoclipTicksToFlag = 3,   -- consecutive ticks fully inside collidable geometry
		NoclipSeverity = 14,

		MaxVelocity = 500,       -- fling / launch exploit ceiling
		MaxCoordinate = 50000,   -- out-of-map coordinate ceiling
		SanitySeverity = 25,     -- NaN positions, flings: always corrected immediately
	},

	Combat = {
		Enabled = true,
		DefaultMaxRange = 18,
		RangeTolerance = 4,      -- studs of slack for interpolation error
		RequireLineOfSight = true,
		DefaultShotsPerSecond = 6,
		DefaultBurst = 3,
		RangeSeverity = 8,
		SightSeverity = 6,
		RateSeverity = 10,
	},

	Remotes = {
		Enabled = true,
		DefaultRate = 10,        -- calls per second sustained
		DefaultBurst = 20,       -- calls allowed back-to-back
		RateSeverity = 5,
		SchemaSeverity = 12,
	},

	History = {
		Seconds = 1.5,           -- position rewind window used for lag compensation
	},

	Ownership = {
		Enabled = true,
		Tag = "ServerOwned",     -- CollectionService tag: forces server physics ownership
	},
}
