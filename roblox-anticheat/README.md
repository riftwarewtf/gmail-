# Roblox Server-Side Anti-Cheat

Luau, server-only. Roblox Studio (any recent version) + Rojo optional.

## What server-side can and can't see

A client can only reach your server three ways, so those are the only three
things worth checking:

1. **Its own character's physics.** The client owns the network ownership of
   its character, so speed/fly/noclip hacks have to actually move the root
   part — and the server sees that movement. Position is the ground truth.
2. **Remote events and functions.** Everything a client *claims* arrives here.
3. **Physics ownership of nearby unanchored parts.** The fling-exploit door.

Things that are **not** worth checking server-side, because client writes to
them never replicate: `Humanoid.WalkSpeed`, `JumpPower`, `Health`, part
`Size`/`Transparency`, locally created instances. A speed hacker *does* set
their own WalkSpeed, but the server still reads its own value — which is
exactly why the speed check compares distance travelled against the
*server's* WalkSpeed instead of asking the client anything.

## Install

**Studio (manual)**

1. `ServerScriptService` → insert a `ModuleScript`, rename it `AntiCheat`,
   paste `AntiCheat/init.lua` into it.
2. Inside it, add ModuleScripts `Config`, `Violations`, `History`, `Bucket`
   from the matching files.
3. Inside it, add a `Folder` named `Checks`, with ModuleScripts `Movement`,
   `Combat`, `Remotes`, `Ownership`.
4. `ServerScriptService` → insert a `Script` named `Bootstrap`, paste
   `Bootstrap.server.lua`.
5. Press Play. Console prints `[AntiCheat] started at 10 Hz`.

**Rojo**

```
rojo serve default.project.json
```

Final tree:

```
ServerScriptService
├── AntiCheat (ModuleScript)
│   ├── Config
│   ├── Violations
│   ├── History
│   ├── Bucket
│   └── Checks (Folder)
│       ├── Movement
│       ├── Combat
│       ├── Remotes
│       └── Ownership
└── Bootstrap (Script)
```

## Usage

```lua
local AntiCheat = require(game.ServerScriptService.AntiCheat)
AntiCheat.start()
```

**Teleport players through it**, otherwise your own code trips the speed check:

```lua
AntiCheat.teleport(player, CFrame.new(0, 50, 0))
AntiCheat.exempt(player, 2)   -- ragdoll, knockback, scripted flight
```

**Bind remotes through it** instead of `OnServerEvent`:

```lua
local t = AntiCheat.Remotes.t

AntiCheat.bind(buyItem, {
	name = "BuyItem",
	rate = 4, burst = 6,
	args = { t.string({ maxLength = 32, pattern = "^%w+$" }) },
}, function(player, itemId)
	-- only reaches here if the player isn't flooding and itemId is a sane string
end)
```

Validators: `t.number{min,max}`, `t.integer{...}`, `t.string{maxLength,
minLength,pattern,oneOf}`, `t.boolean()`, `t.vector3{maxMagnitude}`,
`t.instance(className, {ancestor})`, `t.listOf(inner, maxCount)`,
`t.optional(inner)`, `t.any()`.

**Gate damage** on client-reported hits:

```lua
local ok, reason = AntiCheat.validateHit(player, {
	target = targetPlayer,
	weapon = "rifle",
	maxRange = 300,
	shotsPerSecond = 10,
	burst = 3,
})
if ok then humanoid:TakeDamage(25) end
```

Fire rate, range (with the target rewound by the shooter's ping), and line of
sight. Range + LOS is what kills a silent-aim exploit: the client can claim any
victim it likes, but it can't put a wall somewhere it isn't.

**Pin physics parts to the server** so they can't be used to fling:

```lua
game:GetService("CollectionService"):AddTag(part, "ServerOwned")
-- or
AntiCheat.Ownership.claim(part)
```

**Hook the ladder** for your own punishments:

```lua
AntiCheat.Violations.onAction("rubberband", function(player, check, score) end)
AntiCheat.Violations.getScore(player)   -- current decaying score
AntiCheat.Violations.getLog(player)     -- last 60 pieces of evidence
```

## How the score works

Checks never punish. They report evidence with a severity, the score decays at
`Score.DecayPerSecond`, and the highest ladder rung the score reaches fires:
log at 15, rubberband at 35, kick at 70. One lag spike costs 6 points and
bleeds off in four seconds; an actual speed hack stacks to a kick in under ten.

`Config.Studio.DisablePunishments` keeps you from kicking yourself while
testing — it logs what it *would* have done.

## Tuning before you ship

- **Scripted movement** (dashes, grapples, launchers, conveyors, moving
  platforms, vehicles) → wrap it in `AntiCheat.exempt(player, seconds)` or
  raise `Movement.SpeedBuffer`.
- **Flight false positives** come from standing on non-collidable floors.
  Either make the floor collidable or exempt that zone.
- **Noclip false positives** come from collidable decoration players can stand
  inside. Shrink it, set `CanCollide = false`, or raise
  `Movement.NoclipTicksToFlag`.
- `PlatformStanding` is in the trusted-state list because legit
  platform standing needs it, and a client *can* set that state itself. Noclip
  and sanity checks still run in every state, so the bypass only buys a hacker
  the speed and flight checks. Drop it from `SAFE_STATES` in
  `Checks/Movement.lua` if your game has no moving platforms.
- Run with `DecayPerSecond` high and the kick rung off for a week, read the
  warnings, *then* turn the ladder on. Shipping an untuned anti-cheat kicks
  honest players.
