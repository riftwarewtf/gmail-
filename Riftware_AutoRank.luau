local CONFIG = {
    AutoRankEnabled = true,
    AutoClaimRewards = true,
    AutoFarm = true,
    AutoHatch = true,
    AlwaysHatch = false,
    AutoCraftGoldRainbow = true,
    AutoUsePotions = true,
    AutoUpgradePotions = true,
    AutoUpgradeEnchants = true,
    AutoUseFruits = true,
    AutoUseFlags = true,
    AutoSpawnEvents = true,
    AutoBuyZones = true,
    AutoWorldTeleport = true,
    InfinitePetSpeed = true,
    SuperMagnet = true,
    DisableHatchAnimation = true,
    AutoEquipBestPets = true,
    TryRankUpRemote = false,
    FarmTick = 0.25,
    HatchDelay = 0.75,
    HatchMaxDistance = 85,
    ControllerTick = 1.0,
    CraftTick = 4.0,
    EventTick = 3.0,
    ZonePositionTolerance = 25,
    MaxInventoryPotionTier = 10,
    PotionUsePriority = { "Lucky", "Coins", "Diamonds", "Treasure Hunter", "Damage" },
    PotionUpgradePriority = { "Coins", "Diamonds", "Lucky", "Treasure Hunter", "Damage" },
    EnchantUpgradePriority = { "Coins", "Diamonds", "Tap Power", "Criticals", "Lucky Eggs", "Strong Pets", "Treasure Hunter" },
    FruitUsePriority = { "Apple", "Orange", "Pineapple", "Banana", "Watermelon", "Rainbow" },
    AllowShinyFruit = false,
    FlagPriority = { "Coins Flag", "Diamonds Flag", "Hasty Flag", "Strength Flag", "Magnet Flag", "Fortune Flag", "Shiny Flag" },
    CoinJarPriority = { "Basic Coin Jar", "Giant Coin Jar", "Magic Coin Jar" },
    ProtectedPetIds = {},
    UseShinyPetsAsFodder = false,
    ReexecSource = nil,
    WorkspaceFile = "Riftware_AutoRank.luau",
    ShowGui = true,
    GuiToggleKey = Enum.KeyCode.RightControl,
}

local VERSION = "1.0.0"
local TAG = "[Riftware] "
local STATE_FILE = "Riftware_AutoRank_State.json"
local STATE_FILE_MAX_AGE = 900
local MAX_CRAFT_PER_CALL = 50
local MAX_UPGRADE_PER_CALL = 25
local MAX_CLAIM_ATTEMPTS = 6
local CLAIM_SLOW_RETRY = 60
local GUI_WIDTH = 300

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

local WORLD_PLACE_IDS = {
    [8737899170] = 1,
    [16498369169] = 2,
    [17503543197] = 3,
    [140403681187145] = 4,
}

local GOAL_TYPE_NAMES = {
    [1] = "BREAKABLE", [2] = "PET", [3] = "EGG", [4] = "GOLD_PET", [5] = "RAINBOW_PET", [6] = "ZONE",
    [7] = "CURRENCY", [8] = "MINI_CHEST", [9] = "DIAMOND_BREAKABLE", [10] = "BUY_POTION", [11] = "BUY_ENCHANT",
    [12] = "UPGRADE_POTION", [13] = "UPGRADE_ENCHANT", [14] = "COLLECT_POTION", [15] = "COLLECT_ENCHANT",
    [18] = "FREE_GIFT", [19] = "FUSE_PETS", [20] = "BEST_EGG", [21] = "CURRENT_BREAKABLE", [22] = "SPAWN_OBBY",
    [23] = "MINEFIELD", [24] = "ATLANTIS", [25] = "DIGSITE", [26] = "FISHING", [27] = "ICE_OBBY",
    [28] = "PYRAMID_OBBY", [29] = "JUNGLE_OBBY", [30] = "CHEST_RUSH", [31] = "COIN_JAR", [32] = "COMET",
    [33] = "USE_FLAG", [34] = "USE_POTION", [35] = "USE_FRUIT", [36] = "SLED_RACE", [37] = "BEST_COIN_JAR",
    [38] = "BEST_COMET", [39] = "BEST_MINI_CHEST", [40] = "BEST_GOLD_PET", [41] = "BEST_RAINBOW_PET",
    [42] = "HATCH_RARE_PET", [43] = "BEST_PINATA", [44] = "BEST_LUCKYBLOCK", [45] = "ADVANCED_DIGSITE",
    [46] = "ADVANCED_FISHING", [47] = "INDEX_PET", [66] = "PINATA", [67] = "LUCKYBLOCK", [68] = "RANDOM_COIN_JAR",
    [69] = "RANDOM_COMET", [70] = "RANDOM_PINATA", [71] = "RANDOM_LUCKYBLOCK", [72] = "RANDOM_MINI_CHEST",
    [75] = "SUPERIOR_MINI_CHEST", [76] = "BEST_SUPERIOR_MINI_CHEST", [77] = "RANDOM_SUPERIOR_MINI_CHEST",
    [80] = "EQUIP_PET", [81] = "SPECIFIC_ZONE",
}

local function makeSet(list)
    local s = {}
    for _, v in ipairs(list) do s[v] = true end
    return s
end

local FARM_GOALS = makeSet({ 1, 21, 9, 7, 14, 15, 8, 39, 75, 76 })
local CHEST_GOALS = makeSet({ 8, 39, 75, 76 })
local HATCH_GOALS = makeSet({ 20, 42, 3, 2 })
local EGG_COUNT_GOALS = makeSet({ 20, 3 })
local GOLD_GOALS = makeSet({ 40, 4 })
local RAINBOW_GOALS = makeSet({ 41, 5 })
local BEST_EGG_ONLY_CRAFT = makeSet({ 40, 41 })

local T_ZONE, T_DIAMOND, T_UPGRADE_POTION, T_UPGRADE_ENCHANT = 6, 9, 12, 13
local T_USE_FLAG, T_USE_POTION, T_USE_FRUIT = 33, 34, 35

local EVENT_GOAL_KIND = {
    [38] = "Comet", [32] = "Comet",
    [43] = "Pinata", [66] = "Pinata",
    [44] = "LuckyBlock", [67] = "LuckyBlock",
    [37] = "CoinJar", [31] = "CoinJar",
}
local EVENT_DEFS = {
    Comet = { items = { "Comet" }, remote = "Comet_Spawn", label = "comet", match = { "comet" } },
    Pinata = { items = { "Mini Pinata" }, remote = "MiniPinata_Consume", label = "pinata", match = { "pinata" } },
    LuckyBlock = { items = { "Mini Lucky Block" }, remote = "MiniLuckyBlock_Consume", label = "lucky block", match = { "luckyblock" } },
    CoinJar = { items = CONFIG.CoinJarPriority, remote = "CoinJar_Spawn", label = "coin jar", match = { "coinjar" } },
}
local EVENT_BREAKABLE_WORDS = { "comet", "pinata", "jar", "lucky", "chest" }

local POTION_TIER_REQ_FALLBACK = { 3, 3, 4, 5, 5, 5, 5, 5, 7, 7, 7 }
local ENCHANT_TIER_REQ_FALLBACK = { 3, 3, 3, 5, 5, 5, 5, 5, 8, 8 }

local function int(x)
    x = tonumber(x) or 0
    return tostring(math.floor(x + 0.5))
end

local function fmt(f, ...)
    if select("#", ...) == 0 then return tostring(f) end
    local ok, s = pcall(string.format, tostring(f), ...)
    if ok then return s end
    local parts = { tostring(f) }
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    return table.concat(parts, " ")
end

local function log(f, ...)
    print(TAG .. fmt(f, ...))
end

local warnAt = {}
local function warnlog(key, f, ...)
    local now = os.clock()
    local last = warnAt[tostring(key)]
    if last and now - last < 30 then return end
    warnAt[tostring(key)] = now
    warn(TAG .. fmt(f, ...))
end

local logAt = {}
local function logEvery(key, seconds, f, ...)
    local now = os.clock()
    local last = logAt[tostring(key)]
    if last and now - last < seconds then return end
    logAt[tostring(key)] = now
    log(f, ...)
end

local onceDone = {}
local function logOnce(key, f, ...)
    key = tostring(key)
    if onceDone[key] then return end
    onceDone[key] = true
    log(f, ...)
end

local function warnOnce(key, f, ...)
    key = tostring(key)
    if onceDone[key] then return end
    onceDone[key] = true
    warn(TAG .. fmt(f, ...))
end

local function resetOnce(prefix)
    for k in pairs(onceDone) do
        if string.sub(k, 1, #prefix) == prefix then onceDone[k] = nil end
    end
end

local genv = (type(getgenv) == "function" and getgenv()) or _G
if type(genv.RiftwareAutoRank) == "table" and type(genv.RiftwareAutoRank.Stop) == "function" then
    pcall(genv.RiftwareAutoRank.Stop)
    task.wait(0.25)
end

local IDENTITY_GAME, IDENTITY_EXEC = 2, 8
local canSetIdentity = type(setthreadidentity) == "function"

local function gcall(fn, ...)
    if type(fn) ~= "function" then
        return false, "gcall: not a function"
    end
    if canSetIdentity then pcall(setthreadidentity, IDENTITY_GAME) end
    local r = table.pack(pcall(fn, ...))
    if canSetIdentity then pcall(setthreadidentity, IDENTITY_EXEC) end
    return table.unpack(r, 1, r.n)
end

local function gval(fn, ...)
    local ok, a, b, c, d = gcall(fn, ...)
    if ok then return a, b, c, d end
    return nil
end

local function isfn(mod, name)
    return type(mod) == "table" and type(mod[name]) == "function"
end

local state = {
    alive = true,
    enabled = CONFIG.AutoRankEnabled ~= false,
    startedAt = os.clock(),
    rank = nil,
    goals = {},
    goalsByType = {},
    plan = { hatch = false, hatchReasons = {}, hatchEggOnly = false, hatchRemaining = nil },
    action = "starting",
    counters = { hatched = 0, claimed = 0, crafted = 0, itemsUsed = 0, farmTicks = 0, eventTargets = 0 },
    persist = { lastWorldSwitch = 0 },
    worldSwitching = false,
    worldSwitchAt = 0,
    worldMismatch = false,
    world = nil,
    hopping = false,
    returnAfterHatch = nil,
    lastRank = nil,
    claimedAt = {},
    claimAttempts = {},
    pendingClaims = {},
    trackCompleteLoggedRank = nil,
    trackCompleteAt = nil,
    rankUpFiredRank = nil,
    lastZoneBuyAt = 0,
    craftHatchReason = nil,
    lastEventSpawn = {},
    eventBackoffUntil = {},
    flagRetryAt = 0,
    farmPets = 0,
    farmTargets = 0,
    queued = false,
}

local connections = {}
local function track(conn)
    if conn then connections[#connections + 1] = conn end
    return conn
end

local restoreFns = {}
local persistHook = nil
local gui = nil
local stopped = false
local handle

local function Stop()
    if stopped then return end
    stopped = true
    state.alive = false
    state.action = "stopped"
    for _, c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    connections = {}
    for _, fn in ipairs(restoreFns) do
        pcall(fn)
    end
    restoreFns = {}
    if gui then
        pcall(function() gui:Destroy() end)
        gui = nil
    end
    if persistHook then pcall(persistHook) end
    if genv.RiftwareAutoRank == handle then
        genv.RiftwareAutoRank = nil
    end
    print(TAG .. "stopped")
end

handle = { Stop = Stop, Config = CONFIG, State = state, Version = VERSION }
genv.RiftwareAutoRank = handle

local G = {}

local MODULE_PATHS = {
    Save = { "Library", "Client", "Save" },
    Network = { "Library", "Client", "Network" },
    Directory = { "Library", "Directory" },
    RanksUtil = { "Library", "Util", "RanksUtil" },
    RankCmds = { "Library", "Client", "RankCmds" },
    ZoneCmds = { "Library", "Client", "ZoneCmds" },
    ZonesUtil = { "Library", "Util", "ZonesUtil" },
    EggsUtil = { "Library", "Util", "EggsUtil" },
    EggCmds = { "Library", "Client", "EggCmds" },
    MapCmds = { "Library", "Client", "MapCmds" },
    QuestCmds = { "Library", "Client", "QuestCmds" },
    PotionCmds = { "Library", "Client", "PotionCmds" },
    FruitCmds = { "Library", "Client", "FruitCmds" },
    FlexibleFlagCmds = { "Library", "Client", "FlexibleFlagCmds" },
    RandomEventCmds = { "Library", "Client", "RandomEventCmds" },
    InstancingCmds = { "Library", "Client", "InstancingCmds" },
    PlayerPet = { "Library", "Client", "PlayerPet" },
    PetCmds = { "Library", "Client", "PetCmds" },
    CurrencyCmds = { "Library", "Client", "CurrencyCmds" },
    PlaceFile = { "Library", "Modules", "PlaceFile" },
    CalcPotionsPerTierRequired = { "Library", "Balancing", "CalcPotionsPerTierRequired" },
    CalcEnchantsPerTierRequired = { "Library", "Balancing", "CalcEnchantsPerTierRequired" },
}
local OPTIONAL_MODULE_PATHS = {
    WorldsUtil = { "Library", "Util", "WorldsUtil" },
    EnchantCmds = { "Library", "Client", "EnchantCmds" },
    UpgradeCmds = { "Library", "Client", "UpgradeCmds" },
}

local function findPath(root, path, timeout)
    local inst = root
    for _, name in ipairs(path) do
        if not inst then return nil end
        local child = inst:FindFirstChild(name)
        if not child then
            local ok, res = pcall(function() return inst:WaitForChild(name, timeout or 5) end)
            child = ok and res or nil
        end
        inst = child
    end
    return inst
end

local function loadModule(key, path, optional)
    if G[key] ~= nil then return G[key] end
    local inst = findPath(RS, path, optional and 1 or 5)
    if not inst then
        if not optional then
            warnlog("mod-" .. key, "module %s not found (ReplicatedStorage.%s) - features needing it are disabled", key, table.concat(path, "."))
        end
        return nil
    end
    local ok, mod = gcall(require, inst)
    if not ok then
        warnlog("mod-" .. key, "require(%s) failed: %s", key, tostring(mod))
        return nil
    end
    G[key] = mod
    return mod
end

local function directoryTable(name)
    if type(G.Directory) == "table" then
        local ok, t = gcall(function() return G.Directory[name] end)
        if ok and type(t) == "table" then return t end
    end
    return loadModule(name, { "Library", "Directory", name }, true)
end

local function loadModules()
    for key, path in pairs(MODULE_PATHS) do
        if not state.alive then return end
        loadModule(key, path, false)
    end
    for key, path in pairs(OPTIONAL_MODULE_PATHS) do
        if not state.alive then return end
        loadModule(key, path, true)
    end
    G.Ranks = directoryTable("Ranks")
    G.Zones = directoryTable("Zones")
    G.Eggs = directoryTable("Eggs")
    G.Potions = directoryTable("Potions")
    G.Enchants = directoryTable("Enchants")
    G.RandomEvents = directoryTable("RandomEvents")
    local missing = {}
    for key in pairs(MODULE_PATHS) do
        if G[key] == nil then missing[#missing + 1] = key end
    end
    if #missing > 0 then
        table.sort(missing)
        warnlog("mod-missing", "missing modules: %s", table.concat(missing, ", "))
    end
end

local function netFire(name, ...)
    if not isfn(G.Network, "Fire") then return false, "Network.Fire unavailable" end
    return gcall(G.Network.Fire, name, ...)
end

local function netInvoke(name, ...)
    if not isfn(G.Network, "Invoke") then return false, "Network.Invoke unavailable" end
    return gcall(G.Network.Invoke, name, ...)
end

local function netUnreliable(name, ...)
    if isfn(G.Network, "UnreliableFire") then
        return gcall(G.Network.UnreliableFire, name, ...)
    end
    return false, "Network.UnreliableFire unavailable"
end

local function getSave()
    if not isfn(G.Save, "Get") then return nil end
    local ok, s = gcall(G.Save.Get)
    if ok and type(s) == "table" then return s end
    return nil
end

local function readStateFile()
    if type(isfile) ~= "function" or type(readfile) ~= "function" then return nil end
    local ok, data = pcall(function()
        if not isfile(STATE_FILE) then return nil end
        local raw = readfile(STATE_FILE)
        if type(raw) ~= "string" or raw == "" then return nil end
        return HttpService:JSONDecode(raw)
    end)
    if ok and type(data) == "table" then return data end
    return nil
end

local function writeStateFile()
    if type(writefile) ~= "function" then return end
    pcall(function()
        local payload = {
            version = VERSION,
            savedAt = os.time(),
            lastWorldSwitch = state.persist.lastWorldSwitch or 0,
            counters = state.counters,
        }
        writefile(STATE_FILE, HttpService:JSONEncode(payload))
    end)
end
persistHook = writeStateFile

local function restoreStateFile()
    local data = readStateFile()
    if not data then return end
    state.persist.lastWorldSwitch = tonumber(data.lastWorldSwitch) or 0
    local savedAt = tonumber(data.savedAt) or 0
    if type(data.counters) == "table" and os.time() - savedAt < STATE_FILE_MAX_AGE then
        for k, v in pairs(data.counters) do
            if type(v) == "number" and state.counters[k] ~= nil then
                state.counters[k] = v
            end
        end
        log("Restored counters from %s", STATE_FILE)
    end
end

local function queueSelf(verbose)
    if state.queued then return true end
    if type(queue_on_teleport) ~= "function" then
        if verbose then
            warnlog("queue-missing", "queue_on_teleport is not available - the script will not survive a world teleport")
        end
        return false
    end
    local src = nil
    if type(CONFIG.ReexecSource) == "string" and #CONFIG.ReexecSource > 0 then
        src = CONFIG.ReexecSource
    elseif type(CONFIG.WorkspaceFile) == "string" and type(isfile) == "function" then
        local ok, exists = pcall(isfile, CONFIG.WorkspaceFile)
        if ok and exists then
            src = string.format(
                'local ok, err = pcall(function() local f, e = loadstring(readfile(%q)); assert(f, e); f() end) if not ok then warn("[Riftware reexec] " .. tostring(err)) end',
                CONFIG.WorkspaceFile)
        end
    end
    if not src then
        if verbose then
            warnlog("queue-nofile", "cannot re-queue: put this file in the Potassium workspace folder as %s (or set CONFIG.ReexecSource)", tostring(CONFIG.WorkspaceFile))
        end
        return false
    end
    local ok, err = pcall(queue_on_teleport, src)
    if ok then
        state.queued = true
        log("Re-execution queued for the next place teleport")
    else
        warnlog("queue-fail", "queue_on_teleport failed: %s", tostring(err))
    end
    return ok
end

local cache = { zoneId = nil, zoneAt = 0, zone = nil, egg = nil, eggAt = 0, maxHatch = nil, maxHatchAt = 0, breakPart = nil, breakPartZone = nil }

local function invalidateCaches()
    cache.zoneAt = 0
    cache.eggAt = 0
    cache.maxHatchAt = 0
    cache.breakPart = nil
end

local function getHRP()
    local ch = LocalPlayer and LocalPlayer.Character
    return ch and ch:FindFirstChild("HumanoidRootPart") or nil
end

local instanceCache = { at = -1e9, value = false }
local function inInstance()
    local now = os.clock()
    if now - instanceCache.at < 1 then return instanceCache.value end
    local v = false
    if isfn(G.InstancingCmds, "IsInInstance") then
        v = gval(G.InstancingCmds.IsInInstance) == true
    end
    instanceCache.at = now
    instanceCache.value = v
    return v
end

local function currentWorld()
    local pf = G.PlaceFile
    if type(pf) == "table" then
        for n = 1, 4 do
            local v = pf["IsWorld" .. n]
            if type(v) == "function" then
                local ok, r = gcall(v)
                v = ok and r or nil
            end
            if v == true then return n end
        end
    end
    if isfn(G.WorldsUtil, "GetWorldNumber") then
        local n = gval(G.WorldsUtil.GetWorldNumber)
        if type(n) == "number" then return n end
    end
    return WORLD_PLACE_IDS[game.PlaceId]
end

local function bestZoneId()
    local now = os.clock()
    if cache.zoneId and now - cache.zoneAt < 10 then return cache.zoneId end
    if isfn(G.ZoneCmds, "GetMaxOwnedZone") then
        local id = gval(G.ZoneCmds.GetMaxOwnedZone)
        if type(id) == "table" then id = id._id end
        if type(id) == "string" then
            cache.zoneId = id
            cache.zoneAt = now
            cache.zone = type(G.Zones) == "table" and G.Zones[id] or nil
        end
    end
    return cache.zoneId
end

local function bestZone()
    bestZoneId()
    return cache.zone
end

local function bestZoneName()
    local z = bestZone()
    return (z and (z.ZoneName or z._id)) or bestZoneId() or "?"
end

local function bestEgg()
    local now = os.clock()
    if cache.egg and now - cache.eggAt < 10 then
        if cache.egg.part and cache.egg.part.Parent == nil then
            cache.eggAt = 0
        else
            return cache.egg
        end
    end
    if not (isfn(G.EggCmds, "GetHighestEggNumberAvailable") and isfn(G.EggsUtil, "GetIdByNumber")) then
        return cache.egg
    end
    local n = gval(G.EggCmds.GetHighestEggNumberAvailable)
    if type(n) ~= "number" then return cache.egg end
    local id = gval(G.EggsUtil.GetIdByNumber, n)
    if type(id) == "table" then id = id._id end
    if type(id) ~= "string" then return cache.egg end
    local dir = type(G.Eggs) == "table" and G.Eggs[id] or nil
    local petIds = {}
    if dir and type(dir.pets) == "table" then
        for _, e in pairs(dir.pets) do
            if type(e) == "table" and type(e[1]) == "string" then
                petIds[e[1]] = true
            elseif type(e) == "string" then
                petIds[e] = true
            end
        end
    end
    local part = nil
    if isfn(G.EggsUtil, "GetEggPart") then
        local p = gval(G.EggsUtil.GetEggPart, n)
        if typeof(p) == "Instance" then
            if p:IsA("BasePart") then
                part = p
            elseif p:IsA("Model") then
                part = p.PrimaryPart or p:FindFirstChildWhichIsA("BasePart", true)
            end
        end
    end
    cache.egg = { number = n, id = id, dir = dir, petIds = petIds, part = part, name = (dir and dir.name) or id }
    cache.eggAt = now
    return cache.egg
end

local function maxHatch()
    local now = os.clock()
    if cache.maxHatch and now - cache.maxHatchAt < 30 then return cache.maxHatch end
    local n = nil
    if isfn(G.EggCmds, "GetMaxHatch") then
        n = gval(G.EggCmds.GetMaxHatch)
    end
    if type(n) ~= "number" or n < 1 then
        n = cache.maxHatch or 1
    end
    cache.maxHatch = math.max(1, math.floor(n))
    cache.maxHatchAt = now
    return cache.maxHatch
end

local function inventory(category)
    local save = getSave()
    local inv = save and save.Inventory
    local cat = type(inv) == "table" and inv[category] or nil
    if type(cat) ~= "table" then return {} end
    return cat
end

local function stacks(category, predicate)
    local out = {}
    for uid, item in pairs(inventory(category)) do
        if type(item) == "table" then
            local amount = tonumber(item._am) or 1
            if amount >= 1 and (predicate == nil or predicate(item, amount)) then
                out[#out + 1] = { uid = uid, item = item, amount = amount }
            end
        end
    end
    table.sort(out, function(a, b) return a.amount > b.amount end)
    return out
end

local function pickByPriority(list, priority)
    for _, id in ipairs(priority or {}) do
        for _, s in ipairs(list) do
            if s.item.id == id then return s end
        end
    end
    return nil
end

local function orderByPriority(list, priority)
    local rank = {}
    for i, id in ipairs(priority or {}) do rank[id] = i end
    local out = {}
    for _, s in ipairs(list) do out[#out + 1] = s end
    table.sort(out, function(a, b)
        local ra, rb = rank[a.item.id] or 1e9, rank[b.item.id] or 1e9
        if ra ~= rb then return ra < rb end
        return a.amount > b.amount
    end)
    return out
end

local function rankInfo()
    local save = getSave()
    if not save then return nil end
    local info = {}
    info.rankNumber = tonumber(save.Rank) or 1
    info.stars = tonumber(save.RankStars) or 0
    info.rebirths = tonumber(save.Rebirths) or 0
    info.rankId = isfn(G.RanksUtil, "RankIDFromNumber") and gval(G.RanksUtil.RankIDFromNumber, info.rankNumber) or nil
    info.rankDir = (info.rankId ~= nil and type(G.Ranks) == "table") and G.Ranks[info.rankId] or nil
    info.title = (info.rankDir and info.rankDir.Title) or tostring(info.rankId or ("Rank " .. info.rankNumber))
    info.rewards = (info.rankDir and type(info.rankDir.Rewards) == "table") and info.rankDir.Rewards or {}
    local total = nil
    if info.rankId ~= nil and isfn(G.RanksUtil, "GetTotalStarsRequired") then
        total = gval(G.RanksUtil.GetTotalStarsRequired, info.rankId)
    end
    if type(total) ~= "number" then
        total = 0
        for _, rw in ipairs(info.rewards) do
            total += tonumber(type(rw) == "table" and rw.StarsRequired) or 0
        end
    end
    info.totalStars = total
    info.redeemed = type(save.RedeemedRankRewards) == "table" and save.RedeemedRankRewards or {}
    local cnt = 0
    for _, v in pairs(info.redeemed) do
        if v then cnt += 1 end
    end
    info.redeemedCount = cnt
    info.allRedeemed = #info.rewards > 0 and cnt >= #info.rewards
    info.isMax = isfn(G.RankCmds, "IsMaxRank") and gval(G.RankCmds.IsMaxRank) == true
    info.blockedByZone, info.blockedByRebirth = false, false
    if isfn(G.RankCmds, "IsRankBlockedByZone") then
        local ok, bz, br, zn, rn = gcall(G.RankCmds.IsRankBlockedByZone)
        if ok then
            info.blockedByZone = bz == true
            info.blockedByRebirth = br == true
            info.zoneNumberNeeded = zn
            info.rebirthsNeeded = rn
        end
    end
    return info
end

local function earnedUnclaimedRewards(info)
    local out = {}
    if not info then return out end
    local cum = 0
    for i, rw in ipairs(info.rewards) do
        cum += tonumber(type(rw) == "table" and rw.StarsRequired) or 0
        if cum <= info.stars and info.redeemed[tostring(i)] == nil then
            out[#out + 1] = i
        end
    end
    return out
end

local function nextRewardIn(info)
    if not info then return nil end
    local cum = 0
    for _, rw in ipairs(info.rewards) do
        cum += tonumber(type(rw) == "table" and rw.StarsRequired) or 0
        if cum > info.stars then return cum - info.stars end
    end
    return nil
end

local function isSupported(t)
    if FARM_GOALS[t] then return CONFIG.AutoFarm end
    if HATCH_GOALS[t] then return CONFIG.AutoHatch end
    if GOLD_GOALS[t] or RAINBOW_GOALS[t] then return CONFIG.AutoCraftGoldRainbow end
    if EVENT_GOAL_KIND[t] then return CONFIG.AutoSpawnEvents end
    if t == T_USE_POTION then return CONFIG.AutoUsePotions end
    if t == T_UPGRADE_POTION then return CONFIG.AutoUpgradePotions end
    if t == T_UPGRADE_ENCHANT then return CONFIG.AutoUpgradeEnchants end
    if t == T_USE_FRUIT then return CONFIG.AutoUseFruits end
    if t == T_USE_FLAG then return CONFIG.AutoUseFlags end
    if t == T_ZONE then return CONFIG.AutoBuyZones end
    return false
end

local titleCache, titleCacheCount = {}, 0
local function goalTitle(raw, copy)
    local key = tostring(copy.UID) .. ":" .. tostring(copy.Progress)
    local cached = titleCache[key]
    if cached then return cached end
    local title = nil
    if isfn(G.QuestCmds, "MakeTitle") then
        local ok, t = gcall(G.QuestCmds.MakeTitle, raw)
        if ok and type(t) == "string" and #t > 0 then title = t end
    end
    if not title then
        title = (GOAL_TYPE_NAMES[copy.Type] or ("Type " .. tostring(copy.Type))) .. " x" .. int(copy.Amount)
    end
    title = (string.gsub(title, "<[^>]->", ""))
    if titleCacheCount > 200 then
        titleCache, titleCacheCount = {}, 0
    end
    titleCache[key] = title
    titleCacheCount += 1
    return title
end

local function activeGoals()
    local save = getSave()
    local list, byType = {}, {}
    if not save or type(save.Goals) ~= "table" then return list, byType end
    for tier, g in pairs(save.Goals) do
        if type(g) == "table" and g.Type ~= nil then
            local amount = tonumber(g.Amount) or 0
            local progress = tonumber(g.Progress) or 0
            local copy = {
                tier = tier,
                Stars = tonumber(g.Stars) or 0,
                Type = g.Type,
                Amount = amount,
                Progress = progress,
                UID = g.UID,
                remaining = math.max(0, amount - progress),
                PotionTier = g.PotionTier,
                EnchantTier = g.EnchantTier,
                BreakableType = g.BreakableType,
                CurrencyID = g.CurrencyID,
                raw = g,
            }
            copy.title = goalTitle(g, copy)
            copy.supported = isSupported(copy.Type)
            list[#list + 1] = copy
            byType[copy.Type] = byType[copy.Type] or {}
            table.insert(byType[copy.Type], copy)
        end
    end
    table.sort(list, function(a, b)
        if a.Stars ~= b.Stars then return a.Stars > b.Stars end
        return tostring(a.tier) < tostring(b.tier)
    end)
    return list, byType
end

local function goalParam(goal, field)
    local v = goal[field]
    if v == nil and type(goal.raw) == "table" then v = goal.raw[field] end
    if v ~= nil then return v end
    local info = state.rank
    local pools = info and info.rankDir and info.rankDir.Goals
    if type(pools) ~= "table" then return nil end
    local pool = pools[goal.tier]
    if type(pool) ~= "table" then pool = pools[tonumber(goal.tier)] end
    if type(pool) ~= "table" then pool = pools[tostring(goal.tier)] end
    if type(pool) ~= "table" then return nil end
    local fallback = nil
    for _, entry in pairs(pool) do
        if type(entry) == "table" and entry.Type == goal.Type and entry[field] ~= nil then
            if entry.Amount == goal.Amount then return entry[field] end
            if fallback == nil then fallback = entry[field] end
        end
    end
    return fallback
end

local function findSaveGoal(goal)
    local save = getSave()
    if not (save and type(save.Goals) == "table") then return nil, false end
    for _, g in pairs(save.Goals) do
        if type(g) == "table" and g.UID == goal.UID then return g, true end
    end
    return nil, true
end

local function currentRemaining(goal)
    local g, saveOk = findSaveGoal(goal)
    if not saveOk then return goal.remaining end
    if not g then return 0 end
    return math.max(0, (tonumber(g.Amount) or 0) - (tonumber(g.Progress) or 0))
end

local function breakZonePart(zoneId)
    if cache.breakPart and cache.breakPartZone == zoneId and cache.breakPart.Parent then
        return cache.breakPart
    end
    local found = nil
    if isfn(G.ZonesUtil, "GetInteractFolder") then
        local folder = gval(G.ZonesUtil.GetInteractFolder, zoneId)
        if typeof(folder) == "Instance" then
            local bz = folder:FindFirstChild("BREAK_ZONES")
            if bz then
                for _, d in ipairs(bz:GetDescendants()) do
                    if d:IsA("BasePart") then
                        found = d
                        break
                    end
                end
            end
        end
    end
    if not found and isfn(G.MapCmds, "GetCurrentBreakZonePart") and isfn(G.MapCmds, "GetCurrentZone") then
        if gval(G.MapCmds.GetCurrentZone) == zoneId then
            local p = gval(G.MapCmds.GetCurrentBreakZonePart)
            if typeof(p) == "Instance" and p:IsA("BasePart") then found = p end
        end
    end
    cache.breakPart = found
    cache.breakPartZone = zoneId
    return found
end

local function standPosition(zoneId)
    local part = breakZonePart(zoneId)
    if part then return part.Position + Vector3.new(0, 4, 0) end
    if isfn(G.ZonesUtil, "GetTeleportPartLocation") then
        local cf = gval(G.ZonesUtil.GetTeleportPartLocation, zoneId)
        if typeof(cf) == "CFrame" then return cf.Position + Vector3.new(0, 3, 0) end
        if typeof(cf) == "Vector3" then return cf + Vector3.new(0, 3, 0) end
    end
    return nil
end

local function currentZoneInfo()
    local cz = isfn(G.MapCmds, "GetCurrentZone") and gval(G.MapCmds.GetCurrentZone) or nil
    local inBox = isfn(G.MapCmds, "IsInDottedBox") and gval(G.MapCmds.IsInDottedBox) or nil
    return cz, inBox
end

local lastEnsureAt = 0
local function ensureInBestZone()
    if state.hopping or state.worldSwitching or state.worldMismatch then return false end
    local now = os.clock()
    local force = state.returnAfterHatch ~= nil and now >= state.returnAfterHatch
    if not force and now - lastEnsureAt < 3 then return false end
    lastEnsureAt = now
    if inInstance() then
        logEvery("ensure-instance", 30, "In an instance - not teleporting to the break zone")
        return false
    end
    local zoneId = bestZoneId()
    if not zoneId then return false end
    local pos = standPosition(zoneId)
    if not pos then
        logEvery("ensure-nopos", 60, "Cannot resolve the break zone position of %s yet", tostring(zoneId))
        return false
    end
    local hrp = getHRP()
    if not hrp then return false end
    local cz = isfn(G.MapCmds, "GetCurrentZone") and gval(G.MapCmds.GetCurrentZone) or nil
    local dist = (hrp.Position - pos).Magnitude
    if dist > CONFIG.ZonePositionTolerance or (cz ~= nil and cz ~= zoneId) then
        pcall(function()
            hrp.CFrame = CFrame.new(pos)
            hrp.AssemblyLinearVelocity = Vector3.zero
        end)
        state.returnAfterHatch = nil
        logEvery("ensure-tp", 10, "Teleported into the break zone of %s (was %s studs away)", tostring(zoneId), int(dist))
        return true
    end
    state.returnAfterHatch = nil
    return false
end

local function installSpeedHook()
    if type(hookfunction) ~= "function" then
        logOnce("nohook", "hookfunction unavailable - InfinitePetSpeed disabled")
        return
    end
    if not isfn(G.PlayerPet, "CalculateSpeedMultiplier") then
        logOnce("nospeedfn", "PlayerPet.CalculateSpeedMultiplier missing - InfinitePetSpeed disabled")
        return
    end
    local orig = nil
    local ok, err = pcall(function()
        orig = hookfunction(G.PlayerPet.CalculateSpeedMultiplier, function(...)
            if CONFIG.InfinitePetSpeed and state.alive then return math.huge end
            if type(orig) == "function" then return orig(...) end
            return 1
        end)
    end)
    if ok and type(orig) == "function" then
        log("Infinite pet speed hook installed")
    else
        warnlog("speedhook", "pet speed hook failed: %s", tostring(err or "no original returned"))
    end
end

local magnetBackup = setmetatable({}, { __mode = "k" })
local function applyMagnetConfig(r)
    if type(r) ~= "table" then return end
    if CONFIG.SuperMagnet and state.alive then
        if type(r.config) ~= "table" then r.config = {} end
        if magnetBackup[r.config] == nil then
            magnetBackup[r.config] = { orig = r.config.SuperMagnet }
        end
        r.config.SuperMagnet = true
    elseif type(r.config) == "table" and magnetBackup[r.config] then
        r.config.SuperMagnet = magnetBackup[r.config].orig
        magnetBackup[r.config] = nil
    end
end

local function installMagnet()
    local applied = 0
    local function patch(key, fn)
        local mod = G[key] or loadModule(key, OPTIONAL_MODULE_PATHS[key] or MODULE_PATHS[key], true)
        if type(mod) ~= "table" then return end
        pcall(function()
            if type(setreadonly) == "function" then setreadonly(mod, false) end
        end)
        local ok, err = pcall(fn, mod)
        if ok then
            applied += 1
        else
            warnlog("magnet-" .. key, "super magnet patch %s failed: %s", key, tostring(err))
        end
    end
    patch("EnchantCmds", function(e)
        local o = e.GetPower
        if type(o) ~= "function" then error("no GetPower") end
        e.GetPower = function(...)
            local p = ...
            if CONFIG.SuperMagnet and state.alive and (p == "Super Magnet" or p == "Magnet") then return 999 end
            return o(...)
        end
        restoreFns[#restoreFns + 1] = function() e.GetPower = o end
    end)
    patch("UpgradeCmds", function(u)
        local o = u.GetPower
        if type(o) ~= "function" then error("no GetPower") end
        u.GetPower = function(...)
            if CONFIG.SuperMagnet and state.alive and (...) == "Magnet" then return 999 end
            return o(...)
        end
        restoreFns[#restoreFns + 1] = function() u.GetPower = o end
    end)
    patch("InstancingCmds", function(i)
        local g = i.Get
        if type(g) ~= "function" then error("no Get") end
        i.Get = function(...)
            local r = g(...)
            if type(r) == "table" then pcall(applyMagnetConfig, r) end
            return r
        end
        restoreFns[#restoreFns + 1] = function() i.Get = g end
    end)
    if applied > 0 then
        log("Super magnet patches applied (%d/3)", applied)
    else
        warnlog("magnet-none", "no super magnet patch could be applied")
    end
end

local function installNoHatchAnimation()
    if type(getsenv) ~= "function" then
        logOnce("nogetsenv", "getsenv unavailable - hatch animation stays on")
        return
    end
    task.spawn(function()
        local ok, err = pcall(function()
            local function segment(parent, name)
                if not parent then return nil end
                local child = parent:FindFirstChild(name)
                if child then return child end
                return parent:WaitForChild(name, 10)
            end
            local ps = segment(LocalPlayer, "PlayerScripts")
            local scripts = segment(ps, "Scripts")
            local gameFolder = segment(scripts, "Game")
            local eggScript = segment(gameFolder, "Egg Opening Frontend")
            if not eggScript then error("Egg Opening Frontend script not found (waited up to 10 s per segment)") end
            if not state.alive then return end
            local env = getsenv(eggScript)
            if type(env) ~= "table" then error("getsenv returned " .. typeof(env)) end
            local orig = env.PlayEggAnimation
            env.PlayEggAnimation = function() end
            restoreFns[#restoreFns + 1] = function()
                if orig ~= nil then env.PlayEggAnimation = orig end
            end
        end)
        if not state.alive then return end
        if ok then
            log("Hatch animation disabled")
        else
            warnlog("noanim", "could not disable hatch animation: %s", tostring(err))
        end
    end)
end

local function installPatches()
    if CONFIG.InfinitePetSpeed then pcall(installSpeedHook) end
    if CONFIG.SuperMagnet then pcall(installMagnet) end
    if CONFIG.DisableHatchAnimation then pcall(installNoHatchAnimation) end
end

local function installAntiAfk()
    pcall(function()
        if type(getconnections) == "function" then
            for _, c in ipairs(getconnections(LocalPlayer.Idled)) do
                if c.Disable then
                    c:Disable()
                elseif c.Disconnect then
                    c:Disconnect()
                end
            end
        end
    end)
    track(LocalPlayer.Idled:Connect(function()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end))
    log("Anti-AFK installed")
end

local breakAssign = {}
local farmLastTier = 3
local breakablesFolderCache = nil
local lastEquipBestAt = 0

local function breakablesFolder()
    if breakablesFolderCache and breakablesFolderCache.Parent then return breakablesFolderCache end
    local things = workspace:FindFirstChild("__THINGS")
    local f = things and things:FindFirstChild("Breakables") or nil
    breakablesFolderCache = f
    return f
end

local function classifyBreakable(m)
    local id = string.lower(tostring(m:GetAttribute("BreakableID") or ""))
    local class = m:GetAttribute("BreakableClass")
    if class ~= nil and class ~= "Normal" then return 1 end
    for _, w in ipairs(EVENT_BREAKABLE_WORDS) do
        if string.find(id, w, 1, true) then return 1 end
    end
    if string.find(id, "diamond", 1, true) then return 2 end
    return 3
end

local function collectBreakables(zoneId)
    local p1, p2, p3 = {}, {}, {}
    local folder = breakablesFolder()
    if not folder or not zoneId then return p1, p2, p3 end
    for _, m in ipairs(folder:GetChildren()) do
        if m:IsA("Model") and m:GetAttribute("ParentID") == zoneId then
            local uid = m:GetAttribute("BreakableUID")
            if uid ~= nil then
                local pr = classifyBreakable(m)
                if pr == 1 then
                    p1[#p1 + 1] = uid
                elseif pr == 2 then
                    p2[#p2 + 1] = uid
                else
                    p3[#p3 + 1] = uid
                end
            end
        end
    end
    return p1, p2, p3
end

local function petEuids()
    if not isfn(G.PlayerPet, "GetAll") then return {} end
    local ok, out = gcall(function()
        local res = {}
        local all = G.PlayerPet.GetAll()
        if type(all) ~= "table" then return res end
        local belongs = type(G.PlayerPet.BelongsToLocalPlayer) == "function" and G.PlayerPet.BelongsToLocalPlayer or nil
        local unfiltered = {}
        for _, p in pairs(all) do
            if type(p) == "table" and p.euid ~= nil then
                unfiltered[#unfiltered + 1] = p.euid
                local keep = true
                if belongs then
                    local okB, r = pcall(belongs, p)
                    if okB and r == false then keep = false end
                end
                if keep then res[#res + 1] = p.euid end
            end
        end
        if #res == 0 and #unfiltered > 0 then
            logEvery("pets-unfiltered", 60, "BelongsToLocalPlayer rejected all %d pets - using the unfiltered list", #unfiltered)
            return unfiltered
        end
        return res
    end)
    if ok and type(out) == "table" then return out end
    return {}
end

local lastEquipCheckAt = 0
local function maybeEquipBest()
    if not CONFIG.AutoEquipBestPets then return end
    local now = os.clock()
    if now - lastEquipBestAt < 30 or now - lastEquipCheckAt < 5 then return end
    lastEquipCheckAt = now
    if not (isfn(G.PetCmds, "GetEquipped") and isfn(G.PetCmds, "EquipBest")) then return end
    local okEq, eq = gcall(G.PetCmds.GetEquipped)
    if not okEq then
        warnlog("getequipped", "PetCmds.GetEquipped failed (%s) - EquipBest skipped", tostring(eq))
        return
    end
    if type(eq) == "table" then
        if next(eq) ~= nil then return end
    elseif type(eq) == "number" then
        if eq > 0 then return end
    else
        warnlog("getequipped", "PetCmds.GetEquipped returned %s - EquipBest skipped", typeof(eq))
        return
    end
    lastEquipBestAt = now
    local ok, err = gcall(G.PetCmds.EquipBest)
    if ok then
        log("No pets equipped - PetCmds.EquipBest() called")
    else
        warnlog("equipbest", "EquipBest failed: %s", tostring(err))
    end
end

local function wantsDiamonds()
    for _, g in ipairs(state.goalsByType[T_DIAMOND] or {}) do
        if g.remaining > 0 then return true end
    end
    return false
end

local function farmTick()
    if not state.enabled then return end
    if not CONFIG.AutoFarm then return end
    if state.worldSwitching or state.worldMismatch then return end
    if inInstance() then return end
    ensureInBestZone()
    local zoneId = bestZoneId()
    if not zoneId then return end
    local pets = petEuids()
    state.farmPets = #pets
    if #pets == 0 then
        maybeEquipBest()
        return
    end
    local p1, p2, p3 = collectBreakables(zoneId)
    local targets, tier
    if #p1 > 0 then
        targets, tier = p1, 1
    elseif #p2 > 0 and wantsDiamonds() then
        targets, tier = p2, 2
    else
        targets = {}
        for _, u in ipairs(p2) do targets[#targets + 1] = u end
        for _, u in ipairs(p3) do targets[#targets + 1] = u end
        tier = 3
    end
    state.farmTargets = #targets
    if #targets == 0 then return end
    if tier < farmLastTier then
        breakAssign = {}
    end
    farmLastTier = tier

    local live, used, petSet = {}, {}, {}
    for _, u in ipairs(targets) do live[u] = true end
    for _, e in ipairs(pets) do petSet[e] = true end
    for e, u in pairs(breakAssign) do
        if live[u] and petSet[e] then
            used[u] = true
        else
            breakAssign[e] = nil
        end
    end
    local free = {}
    for _, u in ipairs(targets) do
        if not used[u] then free[#free + 1] = u end
    end
    local rr = 0
    local map = {}
    for _, e in ipairs(pets) do
        if breakAssign[e] == nil then
            if #free > 0 then
                breakAssign[e] = table.remove(free, 1)
            else
                rr += 1
                breakAssign[e] = targets[(rr - 1) % #targets + 1]
            end
        end
        map[e] = breakAssign[e]
    end
    if next(map) == nil then return end
    netUnreliable("Breakables_PlayerDealDamage", targets[1])
    local ok, err = netFire("Breakables_JoinPetBulk", map)
    if ok then
        state.counters.farmTicks += 1
    else
        warnlog("farm-fire", "Breakables_JoinPetBulk failed: %s", tostring(err))
    end
end

local function onBreakableAdded(m)
    if not (state.alive and state.enabled and CONFIG.AutoFarm) or state.worldSwitching or state.worldMismatch then return end
    if typeof(m) ~= "Instance" or not m:IsA("Model") then return end
    local zoneId = cache.zoneId or bestZoneId()
    if not zoneId then return end
    local function handle()
        local ok, err = pcall(function()
            if not state.alive or m.Parent == nil then return end
            if m:GetAttribute("ParentID") ~= zoneId then return end
            if classifyBreakable(m) ~= 1 then return end
            local uid = m:GetAttribute("BreakableUID")
            if uid == nil then return end
            if inInstance() then return end
            local pets = petEuids()
            if #pets == 0 then return end
            local map = {}
            for _, e in ipairs(pets) do
                map[e] = uid
                breakAssign[e] = uid
            end
            farmLastTier = 1
            netUnreliable("Breakables_PlayerDealDamage", uid)
            netFire("Breakables_JoinPetBulk", map)
            state.counters.eventTargets += 1
            log("Event breakable '%s' appeared - all pets sent to it (%s caught so far)",
                tostring(m:GetAttribute("BreakableID") or m.Name), int(state.counters.eventTargets))
        end)
        if not ok then warnlog("fastpath", "breakable fast-path error: %s", tostring(err)) end
    end
    if m:GetAttribute("ParentID") == nil then
        task.defer(handle)
    else
        handle()
    end
end

local function installBreakableListener()
    task.spawn(function()
        local folder = nil
        local t0 = os.clock()
        while state.alive and not folder and os.clock() - t0 < 180 do
            folder = breakablesFolder()
            if not folder then task.wait(1) end
        end
        if not folder or not state.alive then
            if state.alive then warnlog("nobreakables", "workspace.__THINGS.Breakables not found - fast path disabled") end
            return
        end
        track(folder.ChildAdded:Connect(onBreakableAdded))
        log("Breakable fast-path listener installed")
    end)
end

local hatchFailures = 0
local hatchBackoffUntil = 0
local hatchNeedsHop = false
local hopFailedEggId = nil

local function hatchAmount()
    local amount = maxHatch()
    local plan = state.plan
    if plan.hatchEggOnly and type(plan.hatchRemaining) == "number" and plan.hatchRemaining > 0 then
        amount = math.min(amount, plan.hatchRemaining)
    end
    return math.max(1, math.floor(amount))
end

local function hatchPlanned()
    return state.enabled and CONFIG.AutoHatch and (CONFIG.AlwaysHatch or state.plan.hatch == true)
end

local function hatchTick()
    if not hatchPlanned() then return end
    if state.worldSwitching or state.worldMismatch then return end
    if os.clock() < hatchBackoffUntil then return end
    if inInstance() then return end
    local egg = bestEgg()
    if not (egg and egg.id) then
        warnlog("no-egg", "cannot resolve the best egg")
        return
    end
    local amount = hatchAmount()
    local hrp = getHRP()
    local part = egg.part
    local far = hrp ~= nil and part ~= nil and part.Parent ~= nil
        and (hrp.Position - part.Position).Magnitude > CONFIG.HatchMaxDistance
    local hopped = false
    if far and hatchNeedsHop and hopFailedEggId ~= egg.id then
        state.hopping = true
        hopped = true
        pcall(function()
            hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 6))
            hrp.AssemblyLinearVelocity = Vector3.zero
        end)
        task.wait(0.2)
    end
    local ok, res, msg = netInvoke("Eggs_RequestPurchase", egg.id, amount)
    if hopped then
        state.hopping = false
        state.returnAfterHatch = os.clock() + 1
    end
    if ok and res == true then
        hatchFailures = 0
        hatchNeedsHop = false
        hopFailedEggId = nil
        state.counters.hatched += amount
        local plan = state.plan
        if plan.hatchEggOnly and type(plan.hatchRemaining) == "number" then
            plan.hatchRemaining -= amount
            if plan.hatchRemaining <= 0 then plan.hatch = false end
        end
        logEvery("hatch-ok", 30, "Hatching %s x%d (total %d)", tostring(egg.name or egg.id), amount, state.counters.hatched)
    else
        hatchFailures += 1
        local delays = { 1, 2, 5 }
        local d = delays[math.min(hatchFailures, 3)]
        hatchBackoffUntil = os.clock() + d
        if hopped then hopFailedEggId = egg.id end
        hatchNeedsHop = far and not hopped and hopFailedEggId ~= egg.id
        local reason = ok and tostring(msg or res) or tostring(res)
        warnlog("hatch-fail", "hatch %s x%d failed (%s) - backing off %d s%s", tostring(egg.id), amount, reason, d,
            hatchNeedsHop and ", retrying next to the egg" or "")
    end
end

local function protectedSet()
    local s = {}
    for _, id in ipairs(CONFIG.ProtectedPetIds or {}) do s[id] = true end
    return s
end

local function fodderStacks(ptWanted, allowedIds)
    local prot = protectedSet()
    return stacks("Pet", function(item, _)
        if type(item.id) ~= "string" then return false end
        local pt = tonumber(item.pt) or 0
        if pt ~= ptWanted then return false end
        if allowedIds and not allowedIds[item.id] then return false end
        if item.sh == true and not CONFIG.UseShinyPetsAsFodder then return false end
        if prot[item.id] then return false end
        return true
    end)
end

local function craftAllowedIds(goal)
    if BEST_EGG_ONLY_CRAFT[goal.Type] then
        local egg = bestEgg()
        if not (egg and egg.petIds and next(egg.petIds) ~= nil) then
            warnlog("craft-noegg", "cannot resolve best-egg pets for goal %s", tostring(goal.title))
            return false, nil, nil
        end
        return true, egg.petIds, tostring(egg.name or egg.id)
    end
    return true, nil, "best-egg"
end

local function goldGoalCap()
    local cap = nil
    for t in pairs(GOLD_GOALS) do
        for _, g in ipairs(state.goalsByType[t] or {}) do
            local live = findSaveGoal(g)
            if live then
                local r = math.max(0, (tonumber(live.Amount) or 0) - (tonumber(live.Progress) or 0))
                cap = cap and math.min(cap, r) or r
            end
        end
    end
    return cap
end

local function craftGoldenFrom(normalStacks, rem, logSuffix, capFn)
    local crafted = 0
    for _, s in ipairs(normalStacks) do
        if rem <= 0 then break end
        while rem > 0 and s.amount >= 10 and state.alive do
            local k = math.min(math.floor(s.amount / 10), rem, MAX_CRAFT_PER_CALL)
            local ok, res, msg = netInvoke("GoldMachine_Activate", s.uid, k)
            if ok and res == true then
                crafted += k
                rem -= k
                s.amount -= k * 10
                state.counters.crafted += k
                log("Crafted %d golden %s%s", k, tostring(s.item.id), logSuffix or "")
                task.wait(0.5)
                if capFn then
                    local c = capFn()
                    if type(c) == "number" then rem = math.min(rem, c) end
                end
            else
                warnlog("gold-fail", "GoldMachine_Activate failed: %s", tostring(ok and (msg or res) or res))
                return crafted, rem, nil
            end
        end
    end
    local best = 0
    for _, s in ipairs(normalStacks) do best = math.max(best, s.amount) end
    return crafted, rem, best
end

local function fodderReason(left, leftover, label, goal)
    if left > 0 and leftover ~= nil then
        local need = math.max(1, left * 10 - leftover)
        return string.format("need %d more normal %s pets for %s", need, tostring(label), GOAL_TYPE_NAMES[goal.Type] or "crafting")
    end
    return nil
end

local function handleGoldCraft(goal)
    local ok, allowed, label = craftAllowedIds(goal)
    if not ok then return nil end
    local rem = currentRemaining(goal)
    if rem <= 0 then return nil end
    local normal = fodderStacks(0, allowed)
    local _, left, leftover = craftGoldenFrom(normal, rem, "", function() return currentRemaining(goal) end)
    return fodderReason(left, leftover, label, goal)
end

local function craftRainbowFrom(goldenStacks, rem, goal)
    for _, s in ipairs(goldenStacks) do
        if rem <= 0 then break end
        while rem > 0 and s.amount >= 10 and state.alive do
            local k = math.min(math.floor(s.amount / 10), rem, MAX_CRAFT_PER_CALL)
            local ok, res, msg = netInvoke("RainbowMachine_Activate", s.uid, k)
            if ok and res == true then
                rem -= k
                s.amount -= k * 10
                state.counters.crafted += k
                log("Crafted %d rainbow %s", k, tostring(s.item.id))
                task.wait(0.5)
                rem = math.min(rem, currentRemaining(goal))
            else
                warnlog("rainbow-fail", "RainbowMachine_Activate failed: %s", tostring(ok and (msg or res) or res))
                return rem, false
            end
        end
    end
    return rem, true
end

local function handleRainbowCraft(goal)
    local okIds, allowed, label = craftAllowedIds(goal)
    if not okIds then return nil end
    local rem = currentRemaining(goal)
    if rem <= 0 then return nil end
    local golden = fodderStacks(1, allowed)
    local okStep
    rem, okStep = craftRainbowFrom(golden, rem, goal)
    if rem <= 0 or not okStep then return nil end
    local goldenById = {}
    for _, s in ipairs(golden) do
        goldenById[s.item.id] = (goldenById[s.item.id] or 0) + s.amount
    end
    local normal = fodderStacks(0, allowed)
    table.sort(normal, function(a, b)
        local ga, gb = goldenById[a.item.id] or 0, goldenById[b.item.id] or 0
        if ga ~= gb then return ga > gb end
        return a.amount > b.amount
    end)
    local src = normal[1]
    if not src then
        return fodderReason(rem * 10, 0, label, goal)
    end
    local goldenNeeded = rem * 10 - (goldenById[src.item.id] or 0)
    if goldenNeeded <= 0 then return nil end
    local goldCap = goldGoalCap()
    if goldCap ~= nil then
        if goldCap <= 0 then
            logEvery("rainbow-goldcap", 30, "Waiting for the gold goal to refresh before crafting golden pets for %s", tostring(goal.title))
            return nil
        end
        goldenNeeded = math.min(goldenNeeded, goldCap)
    end
    local made, left, leftover = craftGoldenFrom({ src }, goldenNeeded, " (for rainbow goal)", goldCap ~= nil and goldGoalCap or nil)
    if made > 0 then
        task.wait(0.75)
        rem = currentRemaining(goal)
        if rem > 0 then
            craftRainbowFrom(fodderStacks(1, allowed), rem, goal)
        end
    end
    return fodderReason(left, leftover, label, goal)
end

local function tierRequirement(kind, srcTier)
    local fn, fb
    if kind == "potion" then
        fn = G.CalcPotionsPerTierRequired
        fb = POTION_TIER_REQ_FALLBACK
    else
        fn = G.CalcEnchantsPerTierRequired
        fb = ENCHANT_TIER_REQ_FALLBACK
    end
    if type(fn) == "function" then
        local n = gval(fn, srcTier)
        if type(n) == "number" and n >= 1 then return math.floor(n) end
    end
    return fb[srcTier] or fb[#fb] or 3
end

local function handleUsePotions(goal)
    local T = tonumber(goalParam(goal, "PotionTier"))
    if not T then
        warnOnce("notier:" .. tostring(goal.UID), "USE_POTION goal '%s' has no PotionTier - skipping", tostring(goal.title))
        return
    end
    local rem = currentRemaining(goal)
    if rem <= 0 then return end
    local n = math.min(rem, 10)
    local used = 0
    while used < n and state.alive do
        local list = stacks("Potion", function(item, _) return tonumber(item.tn) == T end)
        local s = pickByPriority(list, CONFIG.PotionUsePriority) or list[1]
        if not s then
            warnOnce("noitem:" .. tostring(goal.UID), "No tier %d potions left in inventory (%s)", T, tostring(goal.title))
            break
        end
        local ok, err = netFire("Potions: Consume", s.uid, 1)
        if not ok then
            warnlog("potion-fail", "Potions: Consume failed: %s", tostring(err))
            break
        end
        used += 1
        state.counters.itemsUsed += 1
        task.wait(0.4)
    end
    if used > 0 then log("Used %d tier %d potion(s) (%s)", used, T, tostring(goal.title)) end
end

local function upgradeStacks(category, srcTier, priority, dirTable, targetTier)
    local list = stacks(category, function(item, _)
        if tonumber(item.tn) ~= srcTier then return false end
        local dirEntry = type(dirTable) == "table" and item.id ~= nil and dirTable[item.id] or nil
        local maxTier = dirEntry and tonumber(dirEntry.MaxTier) or nil
        if maxTier and maxTier < targetTier then return false end
        return true
    end)
    return orderByPriority(list, priority)
end

local function handleUpgrade(goal, kind)
    local isPotion = kind == "potion"
    local field = isPotion and "PotionTier" or "EnchantTier"
    local T = tonumber(goalParam(goal, field))
    if not T or T < 2 then
        warnOnce("notier:" .. tostring(goal.UID), "%s goal '%s' has no usable %s - skipping", GOAL_TYPE_NAMES[goal.Type] or "upgrade", tostring(goal.title), field)
        return
    end
    if isPotion and T > CONFIG.MaxInventoryPotionTier then
        warnOnce("notier:" .. tostring(goal.UID), "UPGRADE_POTION goal '%s' targets tier %d above MaxInventoryPotionTier (%d) - skipping",
            tostring(goal.title), T, CONFIG.MaxInventoryPotionTier)
        return
    end
    local rem = currentRemaining(goal)
    if rem <= 0 then return end
    local need = tierRequirement(kind, T - 1)
    local dirTable
    if isPotion then dirTable = G.Potions else dirTable = G.Enchants end
    local list = upgradeStacks(isPotion and "Potion" or "Enchant", T - 1,
        isPotion and CONFIG.PotionUpgradePriority or CONFIG.EnchantUpgradePriority,
        dirTable, T)
    local remote = isPotion and "UpgradePotionsMachine_Activate" or "UpgradeEnchantsMachine_Activate"
    local usable = 0
    for _, s in ipairs(list) do
        if rem <= 0 or not state.alive then break end
        if s.amount >= need then
            usable += 1
            local k = math.min(math.floor(s.amount / need), rem, MAX_UPGRADE_PER_CALL)
            local ok, res, msg = netInvoke(remote, s.uid, k)
            if ok and res == true then
                rem -= k
                state.counters.crafted += k
                log("Upgraded %d x %s %s T%d -> T%d", k, tostring(s.item.id), kind, T - 1, T)
                task.wait(0.5)
                rem = math.min(rem, currentRemaining(goal))
            else
                warnlog("upg-fail-" .. kind, "%s failed: %s", remote, tostring(ok and (msg or res) or res))
                break
            end
        end
    end
    if usable == 0 and rem > 0 then
        warnOnce("noitem:" .. tostring(goal.UID), "No tier %d %s stacks with >= %d items to upgrade (%s)", T - 1, kind, need, tostring(goal.title))
    end
end

local function handleUseFruits(goal)
    local rem = currentRemaining(goal)
    if rem <= 0 then return end
    local n = math.min(rem, 10)
    local used = 0
    while used < n and state.alive do
        local list = stacks("Fruit", function(item, _)
            if item.sh == true and not CONFIG.AllowShinyFruit then return false end
            return true
        end)
        local s = pickByPriority(list, CONFIG.FruitUsePriority) or list[1]
        if not s then
            warnOnce("noitem:" .. tostring(goal.UID), "No fruits left in inventory (%s)", tostring(goal.title))
            break
        end
        local ok, err = netFire("Fruits: Consume", s.uid, 1)
        if not ok then
            warnlog("fruit-fail", "Fruits: Consume failed: %s", tostring(err))
            break
        end
        used += 1
        state.counters.itemsUsed += 1
        task.wait(0.4)
    end
    if used > 0 then log("Used %d fruit(s) (%s)", used, tostring(goal.title)) end
end

local function handleUseFlags(goal)
    if os.clock() < state.flagRetryAt then return end
    if state.worldMismatch then return end
    if not isfn(G.FlexibleFlagCmds, "Consume") then
        logOnce("noflagcmds", "FlexibleFlagCmds.Consume unavailable - flag goals are manual")
        return
    end
    local rem = currentRemaining(goal)
    if rem <= 0 then return end
    if inInstance() then return end
    local zoneId = bestZoneId()
    local cz, inBox = currentZoneInfo()
    if cz ~= zoneId or inBox ~= true then
        ensureInBestZone()
        return
    end
    local list = stacks("Misc", function(item, _)
        return type(item.id) == "string" and string.sub(item.id, -5) == " Flag"
    end)
    local s = pickByPriority(list, CONFIG.FlagPriority) or list[1]
    if not s then
        warnOnce("noitem:" .. tostring(goal.UID), "No flags left in inventory (%s)", tostring(goal.title))
        state.flagRetryAt = os.clock() + 60
        return
    end
    local ok, res, msg = gcall(G.FlexibleFlagCmds.Consume, s.item.id, s.uid, 1)
    if ok and res == true then
        state.counters.itemsUsed += 1
        state.flagRetryAt = os.clock() + 5
        log("Placed %s (%s left) for %s", tostring(s.item.id), int(s.amount - 1), tostring(goal.title))
    elseif ok and res == false then
        local m = tostring(msg or "")
        local ml = string.lower(m)
        if string.find(ml, "different flag", 1, true) or string.find(ml, "already", 1, true) then
            state.flagRetryAt = os.clock() + 60
            logEvery("flag-exists", 60, "A flag is already placed in this area (%s) - retrying in 60 s", m)
        else
            state.flagRetryAt = os.clock() + 20
            warnlog("flag-fail", "Flag placement refused: %s", m)
        end
    else
        state.flagRetryAt = os.clock() + 20
        warnlog("flag-err", "FlexibleFlagCmds.Consume error: %s", tostring(res))
    end
end

local function craftOrder(t)
    if GOLD_GOALS[t] then return 1 end
    if RAINBOW_GOALS[t] then return 2 end
    return 3
end

local function craftTick()
    if not state.enabled then return end
    if state.worldSwitching then return end
    local goals = {}
    for _, g in ipairs(state.goals) do
        if g.remaining > 0 then goals[#goals + 1] = g end
    end
    if #goals == 0 then
        state.craftHatchReason = nil
        return
    end
    table.sort(goals, function(a, b)
        local oa, ob = craftOrder(a.Type), craftOrder(b.Type)
        if oa ~= ob then return oa < ob end
        if a.Stars ~= b.Stars then return a.Stars > b.Stars end
        return tostring(a.tier) < tostring(b.tier)
    end)
    local needHatch = nil
    for _, goal in ipairs(goals) do
        if not state.alive then return end
        local t = goal.Type
        local handler, arg = nil, nil
        if GOLD_GOALS[t] and CONFIG.AutoCraftGoldRainbow then
            handler = handleGoldCraft
        elseif RAINBOW_GOALS[t] and CONFIG.AutoCraftGoldRainbow then
            handler = handleRainbowCraft
        elseif t == T_USE_POTION and CONFIG.AutoUsePotions then
            handler = handleUsePotions
        elseif t == T_UPGRADE_POTION and CONFIG.AutoUpgradePotions then
            handler, arg = handleUpgrade, "potion"
        elseif t == T_UPGRADE_ENCHANT and CONFIG.AutoUpgradeEnchants then
            handler, arg = handleUpgrade, "enchant"
        elseif t == T_USE_FRUIT and CONFIG.AutoUseFruits then
            handler = handleUseFruits
        elseif t == T_USE_FLAG and CONFIG.AutoUseFlags then
            handler = handleUseFlags
        end
        if handler then
            local ok, result = pcall(handler, goal, arg)
            if not ok then
                warnlog("handler-" .. tostring(t), "handler for goal type %s failed: %s", tostring(t), tostring(result))
            elseif (GOLD_GOALS[t] or RAINBOW_GOALS[t]) and type(result) == "string" and needHatch == nil then
                needHatch = result
            end
        end
    end
    if needHatch ~= nil then
        logEvery("craft-fodder", 30, "Crafting needs more fodder: %s - hatching the best egg", needHatch)
    end
    state.craftHatchReason = needHatch
end

local function eventKindOf(ev)
    if type(ev) ~= "table" then return nil end
    local names = {}
    if type(ev.dir) == "table" then
        names[#names + 1] = ev.dir._id
        names[#names + 1] = ev.dir.Name
        names[#names + 1] = ev.dir.name
    end
    names[#names + 1] = ev.id
    names[#names + 1] = ev.name
    for _, n in ipairs(names) do
        if type(n) == "string" then
            local norm = string.lower((string.gsub(n, "%s", "")))
            for kind, def in pairs(EVENT_DEFS) do
                for _, m in ipairs(def.match) do
                    if string.find(norm, m, 1, true) then return kind end
                end
            end
        end
    end
    return nil
end

local function activeEventKinds(zoneId)
    local kinds = {}
    if not isfn(G.RandomEventCmds, "GetActive") then return kinds end
    local ok, active = gcall(G.RandomEventCmds.GetActive)
    if not ok or type(active) ~= "table" then return kinds end
    for _, ev in pairs(active) do
        local kind = eventKindOf(ev)
        if kind and (ev.parentID == nil or ev.parentID == zoneId) then
            kinds[kind] = true
        end
    end
    return kinds
end

local function pickMiscStack(ids)
    local set = makeSet(ids or {})
    local list = stacks("Misc", function(item, _) return set[item.id] == true end)
    return pickByPriority(list, ids) or list[1]
end

local function eventTick()
    if not state.enabled then return end
    if not CONFIG.AutoSpawnEvents then return end
    if state.worldSwitching or state.worldMismatch or state.hopping then return end
    local wanted = {}
    for _, goal in ipairs(state.goals) do
        local kind = EVENT_GOAL_KIND[goal.Type]
        if kind and goal.remaining > 0 and wanted[kind] == nil then
            wanted[kind] = goal
        end
    end
    if next(wanted) == nil then return end
    if inInstance() then return end
    local zoneId = bestZoneId()
    if not zoneId then return end
    local cz, inBox = currentZoneInfo()
    if cz ~= zoneId or inBox ~= true then
        logEvery("event-notinbox", 30, "Not inside the dotted box of %s - moving before spawning event items", tostring(zoneId))
        ensureInBestZone()
        return
    end
    local active = activeEventKinds(zoneId)
    local now = os.clock()
    for kind, goal in pairs(wanted) do
        if not state.alive then return end
        local def = EVENT_DEFS[kind]
        if def and not active[kind]
            and now - (state.lastEventSpawn[kind] or -1e9) >= 12
            and now >= (state.eventBackoffUntil[kind] or 0) then
            local rem = currentRemaining(goal)
            if rem > 0 then
                local s = pickMiscStack(def.items)
                if not s then
                    warnOnce("noitem:" .. tostring(goal.UID), "No %s left in inventory (%s)", table.concat(def.items, "/"), tostring(goal.title))
                else
                    local ok, res, msg = netInvoke(def.remote, s.uid)
                    if ok and res == true then
                        state.lastEventSpawn[kind] = now
                        state.counters.itemsUsed += 1
                        log("Spawned %s (%s left) - %s %s/%s", tostring(s.item.id), int(s.amount - 1), def.label,
                            int(goal.Amount - rem + 1), int(goal.Amount))
                    else
                        state.eventBackoffUntil[kind] = now + 10
                        warnlog("event-fail-" .. kind, "%s failed: %s", def.remote, tostring(ok and (msg or res) or res))
                    end
                    task.wait(0.3)
                end
            end
        end
    end
end

local lastWorldAttempt = -1e9

local function worldTeleport(n, zoneId)
    if state.worldSwitching then return end
    if os.clock() - lastWorldAttempt < 30 then return end
    lastWorldAttempt = os.clock()
    n = math.floor(tonumber(n) or 0)
    local now = os.time()
    local last = tonumber(state.persist.lastWorldSwitch) or 0
    if now - last < 90 then
        warnlog("world-loop", "Best zone is in World %d but the last world switch was %d s ago - waiting (anti-loop guard)", n, now - last)
        return
    end
    if not queueSelf(true) then
        warnlog("world-noqueue", "Not teleporting to World %d: re-execution could not be queued (put this file in the Potassium workspace as %s or set CONFIG.ReexecSource, or teleport manually)",
            n, tostring(CONFIG.WorkspaceFile))
        return
    end
    state.persist.lastWorldSwitch = now
    writeStateFile()
    state.worldSwitching = true
    state.worldSwitchAt = os.clock()
    state.action = string.format("Teleporting to World %d", n)
    log("Teleporting to World %d (best zone %s)", n, tostring(zoneId))
    local ok, res, msg = netInvoke(string.format("World%dTeleport", n))
    if not ok or res == false then
        state.worldSwitching = false
        state.persist.lastWorldSwitch = last
        writeStateFile()
        if not ok then
            warnlog("world-fail", "World%dTeleport failed: %s", n, tostring(res))
        else
            warnlog("world-refused", "World%dTeleport refused: %s", n, tostring(msg))
        end
    end
end

local function checkWorld()
    if state.worldSwitching then
        if os.clock() - state.worldSwitchAt > 45 then
            state.worldSwitching = false
            warnlog("world-timeout", "World teleport did not happen within 45 s - resuming")
        end
        return
    end
    local zone = bestZone()
    local cw = currentWorld()
    state.world = cw or state.world
    if not (zone and type(zone.WorldNumber) == "number" and cw) then
        state.worldMismatch = false
        return
    end
    state.worldMismatch = cw ~= zone.WorldNumber
    if not state.worldMismatch then return end
    if CONFIG.AutoWorldTeleport then
        worldTeleport(zone.WorldNumber, bestZoneId())
    else
        logOnce("world:wrong", "Best zone %s is in World %s but we are in World %s - enable AutoWorldTeleport or teleport manually (farming/hatching/events idle; crafting and item use continue)",
            tostring(bestZoneId()), tostring(zone.WorldNumber), tostring(cw))
    end
end

local function onRankUp(info)
    log("RANK UP! now rank %d - %s", info.rankNumber, tostring(info.title))
    for i in pairs(state.pendingClaims) do
        state.counters.claimed += 1
        state.pendingClaims[i] = nil
    end
    state.claimedAt = {}
    state.claimAttempts = {}
    state.trackCompleteLoggedRank = nil
    state.trackCompleteAt = nil
    state.rankUpFiredRank = nil
    state.lastZoneBuyAt = 0
    resetOnce("rank:")
    hatchFailures = 0
    hatchBackoffUntil = 0
    hatchNeedsHop = false
    hopFailedEggId = nil
    invalidateCaches()
    writeStateFile()
end

local function claimRewards(info)
    if not CONFIG.AutoClaimRewards or not info then return end
    for i in pairs(state.pendingClaims) do
        if info.redeemed[tostring(i)] ~= nil then
            state.counters.claimed += 1
            state.pendingClaims[i] = nil
        end
    end
    local now = os.clock()
    for _, i in ipairs(earnedUnclaimedRewards(info)) do
        if not state.alive then return end
        local attempts = state.claimAttempts[i] or 0
        local stuck = attempts >= MAX_CLAIM_ATTEMPTS
        if stuck then
            warnOnce("rank:claimstuck-" .. tostring(i), "Reward #%d was requested %d times but never redeemed - retrying every %d s (RankRewards disabled server-side?)", i, attempts, CLAIM_SLOW_RETRY)
        end
        local last = state.claimedAt[i]
        if last == nil or now - last > (stuck and CLAIM_SLOW_RETRY or 5) then
            local ok, err = netFire("Ranks_ClaimReward", i)
            if ok then
                state.claimedAt[i] = now
                state.claimAttempts[i] = attempts + 1
                state.pendingClaims[i] = now
                if stuck then
                    logEvery("claim-retry-" .. tostring(i), 300, "Retrying reward #%d claim (%s/%s stars)", i, int(info.stars), int(info.totalStars))
                else
                    log("Claimed reward #%d (%s/%s stars)", i, int(info.stars), int(info.totalStars))
                end
                task.wait(0.3)
            else
                warnlog("claim-fail", "Ranks_ClaimReward %d failed: %s", i, tostring(err))
            end
        end
    end
end

local function checkTrackComplete(info)
    if not info or info.isMax then return end
    if not (info.allRedeemed and info.stars >= info.totalStars) then return end
    if info.blockedByZone or info.blockedByRebirth then return end
    if state.trackCompleteLoggedRank ~= info.rankNumber then
        state.trackCompleteLoggedRank = info.rankNumber
        state.trackCompleteAt = os.clock()
        log("Rank %d track complete - waiting for the server rank-up", info.rankNumber)
    end
    if CONFIG.TryRankUpRemote and state.rankUpFiredRank ~= info.rankNumber
        and os.clock() - (state.trackCompleteAt or 0) > 15 then
        state.rankUpFiredRank = info.rankNumber
        local ok, err = netFire("Ranks_RankUp")
        if ok then
            log("Fired Ranks_RankUp (TryRankUpRemote)")
        else
            warnlog("rankup-fail", "Ranks_RankUp failed: %s", tostring(err))
        end
    end
end

local function handleBlockedAndZones(info)
    if info and info.isMax then
        logOnce("rank:max", "Max rank reached - nothing more to rank up")
    end
    if info and info.blockedByZone then
        logOnce("rank:blockedzone", "Rank %d is blocked by zone: zone #%s required%s", info.rankNumber, tostring(info.zoneNumberNeeded),
            CONFIG.AutoBuyZones and " - trying to buy zones" or "")
    end
    if info and info.blockedByRebirth then
        logOnce("rank:blockedrebirth", "Rank %d is blocked by rebirth: %s rebirth(s) required (have %s) - rebirths are not automated",
            info.rankNumber, tostring(info.rebirthsNeeded), int(info.rebirths))
    end
    if not CONFIG.AutoBuyZones then return end
    local reason = nil
    if info and info.blockedByZone then
        reason = "rank blocked by zone"
    else
        for _, g in ipairs(state.goalsByType[T_ZONE] or {}) do
            if g.remaining > 0 then
                reason = "ZONE goal"
                break
            end
        end
    end
    if not reason then return end
    if os.clock() - state.lastZoneBuyAt < 30 then return end
    state.lastZoneBuyAt = os.clock()
    if not isfn(G.ZoneCmds, "GetNextZone") then return end
    local nz = gval(G.ZoneCmds.GetNextZone)
    if type(nz) ~= "table" or nz._id == nil then
        logOnce("rank:nonextzone", "No next zone to buy (all zones owned?) - %s", reason)
        return
    end
    local ok, res, msg = netInvoke("Zones_RequestPurchase", nz._id)
    if not ok then
        warnlog("zonebuy-err", "Zones_RequestPurchase error: %s", tostring(res))
    elseif res == false then
        logEvery("zonebuy-refused", 30, "Zone purchase of %s (%s) refused: %s", tostring(nz._id), reason, tostring(msg))
    else
        log("Requested purchase of zone %s (%s) -> %s", tostring(nz._id), reason, tostring(res))
        invalidateCaches()
    end
end

local function buildPlan()
    local info = state.rank
    local plan = { hatch = false, hatchReasons = {}, hatchEggOnly = true, hatchRemaining = nil, crafting = false, waitingChest = false }
    local parts = {}
    local zone = bestZone()
    if state.worldSwitching then
        state.plan = plan
        state.action = string.format("teleporting to World %s", tostring(zone and zone.WorldNumber or "?"))
        return
    end
    if state.worldMismatch then
        parts[#parts + 1] = string.format("wrong world (best zone is in World %s)", tostring(zone and zone.WorldNumber or "?"))
    elseif info and info.isMax then
        parts[#parts + 1] = "max rank reached"
    elseif CONFIG.AutoFarm then
        local s = string.format("Farming %s (%s pets / %s targets)", tostring(bestZoneName()), int(state.farmPets), int(state.farmTargets))
        if state.counters.eventTargets > 0 then
            s = s .. string.format(", %s events caught", int(state.counters.eventTargets))
        end
        parts[#parts + 1] = s
    end
    for _, goal in ipairs(state.goals) do
        local t = goal.Type
        if goal.remaining > 0 then
            if HATCH_GOALS[t] and CONFIG.AutoHatch then
                plan.hatch = true
                table.insert(plan.hatchReasons, GOAL_TYPE_NAMES[t] or tostring(t))
                if EGG_COUNT_GOALS[t] then
                    plan.hatchRemaining = math.max(plan.hatchRemaining or 0, goal.remaining)
                else
                    plan.hatchEggOnly = false
                end
            elseif (GOLD_GOALS[t] or RAINBOW_GOALS[t]) and CONFIG.AutoCraftGoldRainbow then
                plan.crafting = true
                parts[#parts + 1] = string.format("%s %s/%s", GOLD_GOALS[t] and "gold crafting" or "rainbow crafting", int(goal.Progress), int(goal.Amount))
            elseif EVENT_GOAL_KIND[t] and CONFIG.AutoSpawnEvents then
                local def = EVENT_DEFS[EVENT_GOAL_KIND[t]]
                parts[#parts + 1] = string.format("%s %s/%s", def.label, int(goal.Progress), int(goal.Amount))
            elseif CHEST_GOALS[t] then
                plan.waitingChest = true
            elseif t == T_USE_POTION and CONFIG.AutoUsePotions then
                parts[#parts + 1] = string.format("potions T%s %s/%s", tostring(goalParam(goal, "PotionTier") or "?"), int(goal.Progress), int(goal.Amount))
            elseif t == T_UPGRADE_POTION and CONFIG.AutoUpgradePotions then
                parts[#parts + 1] = string.format("potion upgrades %s/%s", int(goal.Progress), int(goal.Amount))
            elseif t == T_UPGRADE_ENCHANT and CONFIG.AutoUpgradeEnchants then
                parts[#parts + 1] = string.format("enchant upgrades %s/%s", int(goal.Progress), int(goal.Amount))
            elseif t == T_USE_FRUIT and CONFIG.AutoUseFruits then
                parts[#parts + 1] = string.format("fruits %s/%s", int(goal.Progress), int(goal.Amount))
            elseif t == T_USE_FLAG and CONFIG.AutoUseFlags then
                parts[#parts + 1] = string.format("flags %s/%s", int(goal.Progress), int(goal.Amount))
            elseif t == T_ZONE and CONFIG.AutoBuyZones then
                parts[#parts + 1] = "buying zones"
            end
        end
    end
    local fodderOnly = false
    if state.craftHatchReason ~= nil and CONFIG.AutoHatch then
        fodderOnly = not plan.hatch
        plan.hatch = true
        plan.hatchEggOnly = false
        table.insert(plan.hatchReasons, state.craftHatchReason)
    end
    if CONFIG.AlwaysHatch and CONFIG.AutoHatch then
        plan.hatch = true
        plan.hatchEggOnly = false
        fodderOnly = false
    end
    if not plan.hatch then plan.hatchEggOnly = false end
    state.plan = plan
    if plan.hatch and not state.worldMismatch then
        local egg = cache.egg or bestEgg()
        parts[#parts + 1] = string.format("hatching %s x%s%s", tostring(egg and (egg.name or egg.id) or "best egg"), int(hatchAmount()),
            fodderOnly and " (fodder)" or "")
    end
    if plan.waitingChest then parts[#parts + 1] = "waiting for mini chest spawns" end
    if info and info.blockedByZone then
        parts[#parts + 1] = string.format("rank needs zone %s", tostring(info.zoneNumberNeeded or "?"))
    elseif info and info.blockedByRebirth then
        parts[#parts + 1] = string.format("rank needs %s rebirths (have %s)", tostring(info.rebirthsNeeded or "?"), int(info.rebirths))
    end
    if state.hopping then parts[#parts + 1] = "hopping to egg" end
    state.action = #parts > 0 and table.concat(parts, " | ") or "idle"
end

local function controllerTick()
    local info = rankInfo()
    if info then
        state.rank = info
        if state.lastRank ~= nil and info.rankNumber ~= state.lastRank then
            onRankUp(info)
        end
        state.lastRank = info.rankNumber
    end
    local goals, byType = activeGoals()
    state.goals = goals
    state.goalsByType = byType
    for _, goal in ipairs(goals) do
        if not goal.supported then
            logOnce("unsupported-" .. tostring(goal.UID), "Goal '%s' (type %s %s) is not automatable; farming continues",
                tostring(goal.title), tostring(goal.Type), GOAL_TYPE_NAMES[goal.Type] or "")
        end
    end
    if not state.enabled then
        state.plan = { hatch = false, hatchReasons = {}, hatchEggOnly = false, hatchRemaining = nil }
        state.action = "automation paused - rank tracking only"
        return
    end
    if state.worldSwitching then
        buildPlan()
        checkWorld()
        return
    end
    pcall(claimRewards, info)
    pcall(checkTrackComplete, info)
    pcall(handleBlockedAndZones, info)
    pcall(checkWorld)
    buildPlan()
end

local function setEnabled(on)
    on = on ~= false
    if state.enabled == on then return on end
    state.enabled = on
    if on then
        invalidateCaches()
        state.action = "resuming"
        log("Automation enabled")
    else
        state.action = "automation paused - rank tracking only"
        log("Automation paused")
    end
    return on
end

handle.SetEnabled = setEnabled
handle.Toggle = function() return setEnabled(not state.enabled) end
handle.IsEnabled = function() return state.enabled == true end

local buildGui, refreshGui
do
    local PAL = {
        shellTop = Color3.fromRGB(27, 32, 44),
        shellBottom = Color3.fromRGB(13, 16, 23),
        surface = Color3.fromRGB(21, 25, 34),
        raised = Color3.fromRGB(28, 34, 46),
        line = Color3.fromRGB(44, 53, 71),
        text = Color3.fromRGB(234, 240, 248),
        dim = Color3.fromRGB(143, 156, 178),
        faint = Color3.fromRGB(97, 109, 132),
        accent = Color3.fromRGB(26, 214, 182),
        accentAlt = Color3.fromRGB(108, 124, 255),
        warn = Color3.fromRGB(250, 196, 60),
        bad = Color3.fromRGB(246, 94, 110),
    }

    local FONT = {
        black = Enum.Font.GothamBlack,
        bold = Enum.Font.GothamBold,
        med = Enum.Font.GothamMedium,
        body = Enum.Font.Gotham,
    }

    local TW = {
        fast = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        bar = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
        slide = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
        flash = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        pulse = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        sweep = TweenInfo.new(3.2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
        sheen = TweenInfo.new(2.4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
        spin = TweenInfo.new(11, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
    }

    local UI = {
        rows = 4,
        shadow = 20,
        swW = 34,
        swH = 16,
        knob = 10,
        pos = UDim2.new(0.028, 0, 0.11, 0),
        suffix = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" },
        chips = {
            { key = "hatched", caption = "HATCHED" },
            { key = "claimed", caption = "CLAIMED" },
            { key = "crafted", caption = "CRAFTED" },
            { key = "itemsUsed", caption = "ITEMS" },
        },
    }

    local GUI = { rows = {}, stats = {}, shown = {} }

    local function create(class, props, parent)
        local inst = Instance.new(class)
        for k, v in pairs(props) do
            inst[k] = v
        end
        inst.Parent = parent
        return inst
    end

    local function corner(parent, radius)
        return create("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
    end

    local function outline(parent, color, transparency)
        return create("UIStroke", {
            Color = color,
            Transparency = transparency or 0,
            Thickness = 1,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, parent)
    end

    local function inset(parent, top, right, bottom, left)
        return create("UIPadding", {
            PaddingTop = UDim.new(0, top),
            PaddingRight = UDim.new(0, right),
            PaddingBottom = UDim.new(0, bottom),
            PaddingLeft = UDim.new(0, left),
        }, parent)
    end

    local function column(parent, gap)
        return create("UIListLayout", {
            FillDirection = Enum.FillDirection.Vertical,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, gap),
        }, parent)
    end

    local function panel(props, parent, radius)
        props.BorderSizePixel = 0
        props.BackgroundColor3 = props.BackgroundColor3 or PAL.surface
        local frame = create("Frame", props, parent)
        corner(frame, radius or 7)
        return frame
    end

    local function label(props, parent)
        if props.BackgroundTransparency == nil then props.BackgroundTransparency = 1 end
        props.BorderSizePixel = 0
        props.Font = props.Font or FONT.body
        props.TextColor3 = props.TextColor3 or PAL.text
        props.TextSize = props.TextSize or 11
        props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
        return create("TextLabel", props, parent)
    end

    local function tween(inst, info, props)
        local ok, anim = pcall(TweenService.Create, TweenService, inst, info, props)
        if ok and anim then
            anim:Play()
            return anim
        end
        return nil
    end

    local function flash(inst, prop, from, to, info)
        inst[prop] = from
        tween(inst, info or TW.flash, { [prop] = to })
    end

    local function sweep(gradient, info)
        gradient.Offset = Vector2.new(-1, 0)
        tween(gradient, info or TW.sweep, { Offset = Vector2.new(1, 0) })
        return gradient
    end

    local function bar(parent, position, size, radius, sheen)
        local groove = create("Frame", {
            BackgroundColor3 = PAL.raised,
            BorderSizePixel = 0,
            Position = position,
            Size = size,
        }, parent)
        corner(groove, radius)
        local fill = create("Frame", {
            BackgroundColor3 = sheen and Color3.fromRGB(255, 255, 255) or PAL.accentAlt,
            BorderSizePixel = 0,
            Size = UDim2.new(0, 0, 1, 0),
        }, groove)
        corner(fill, radius)
        if sheen then
            sweep(create("UIGradient", {
                Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, PAL.accent),
                    ColorSequenceKeypoint.new(0.5, PAL.accentAlt),
                    ColorSequenceKeypoint.new(1, PAL.accent),
                }),
            }, fill), TW.sheen)
        end
        return groove, fill
    end

    local function setBar(fill, alpha, color)
        alpha = math.clamp(tonumber(alpha) or 0, 0, 1)
        if alpha > 0 then alpha = math.max(alpha, 0.025) end
        if color and fill.BackgroundColor3 ~= color then fill.BackgroundColor3 = color end
        local target = UDim2.new(alpha, 0, 1, 0)
        if fill.Size ~= target then tween(fill, TW.bar, { Size = target }) end
    end

    local function comma(n)
        local s = string.format("%d", math.floor(tonumber(n) or 0))
        local sign = ""
        if string.sub(s, 1, 1) == "-" then
            sign, s = "-", string.sub(s, 2)
        end
        while true do
            local replaced
            s, replaced = string.gsub(s, "^(%d+)(%d%d%d)", "%1,%2")
            if replaced == 0 then break end
        end
        return sign .. s
    end

    local function shortNum(n)
        n = tonumber(n) or 0
        if n < 0 then return "-" .. shortNum(-n) end
        if n < 10000 then return comma(n) end
        local i = 1
        while n >= 1000 and i < #UI.suffix do
            n /= 1000
            i += 1
        end
        local s
        if n < 10 then
            s = string.format("%.2f", n)
        elseif n < 100 then
            s = string.format("%.1f", n)
        else
            s = string.format("%.0f", n)
        end
        if string.find(s, "%.") then
            s = (string.gsub(s, "0+$", ""))
            s = (string.gsub(s, "%.$", ""))
        end
        return s .. UI.suffix[i]
    end

    local function formatTime(total)
        total = math.max(0, math.floor(total))
        return string.format("%02d:%02d:%02d", math.floor(total / 3600), math.floor(total / 60) % 60, total % 60)
    end

    local function guiParent()
        if type(gethui) == "function" then
            local ok, h = pcall(gethui)
            if ok and typeof(h) == "Instance" then return h end
        end
        return CoreGui
    end

    local function iconButton(parent, offsetX, text, hoverColor)
        local btn = create("TextButton", {
            AutoButtonColor = false,
            BackgroundColor3 = PAL.raised,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Font = FONT.bold,
            Text = text,
            TextColor3 = PAL.dim,
            TextSize = 12,
            Position = UDim2.new(1, offsetX, 0.5, -9),
            Size = UDim2.new(0, 18, 0, 18),
        }, parent)
        corner(btn, 5)
        track(btn.MouseEnter:Connect(function()
            tween(btn, TW.fast, { BackgroundTransparency = 0.1, TextColor3 = hoverColor })
        end))
        track(btn.MouseLeave:Connect(function()
            tween(btn, TW.fast, { BackgroundTransparency = 1, TextColor3 = PAL.dim })
        end))
        return btn
    end

    local function buildSwitch(parent)
        local hit = create("TextButton", {
            AutoButtonColor = false,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            Position = UDim2.new(1, -90, 0.5, -11),
            Size = UDim2.new(0, 38, 0, 22),
        }, parent)

        local groove = panel({
            BackgroundColor3 = PAL.line,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.new(0, UI.swW, 0, UI.swH),
        }, hit, 8)
        local ring = outline(groove, PAL.text, 1)
        local glow = panel({
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            ZIndex = 1,
        }, groove, 8)
        create("UIGradient", { Color = ColorSequence.new(PAL.accent, PAL.accentAlt) }, glow)
        local knob = panel({
            BackgroundColor3 = PAL.dim,
            Position = UDim2.new(0, 3, 0.5, -UI.knob / 2),
            Size = UDim2.new(0, UI.knob, 0, UI.knob),
            ZIndex = 2,
        }, groove, UI.knob / 2)

        GUI.switch = { groove = groove, glow = glow, knob = knob }
        track(hit.MouseEnter:Connect(function()
            tween(ring, TW.fast, { Transparency = 0.6 })
        end))
        track(hit.MouseLeave:Connect(function()
            tween(ring, TW.fast, { Transparency = 1 })
        end))
        track(hit.MouseButton1Click:Connect(function()
            setEnabled(not state.enabled)
        end))
        return hit
    end

    local function paintSwitch(on)
        local sw = GUI.switch
        if not sw or GUI.switchOn == on then return end
        GUI.switchOn = on
        tween(sw.glow, TW.slide, { BackgroundTransparency = on and 0 or 1 })
        tween(sw.knob, TW.slide, {
            Position = UDim2.new(0, on and (UI.swW - 3 - UI.knob) or 3, 0.5, -UI.knob / 2),
            BackgroundColor3 = on and PAL.shellBottom or PAL.dim,
        })
    end

    local function sectionCaption(text, parent, order)
        local row = create("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 10),
            LayoutOrder = order,
        }, parent)
        label({
            Text = text,
            Font = FONT.bold,
            TextSize = 9,
            TextColor3 = PAL.faint,
            Size = UDim2.new(0.5, 0, 1, 0),
        }, row)
        return label({
            Text = "",
            Font = FONT.med,
            TextSize = 9,
            TextColor3 = PAL.faint,
            TextXAlignment = Enum.TextXAlignment.Right,
            Position = UDim2.new(0.5, 0, 0, 0),
            Size = UDim2.new(0.5, 0, 1, 0),
        }, row)
    end

    local function buildHeader(main)
        local header = create("Frame", {
            Active = true,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 36),
            LayoutOrder = 1,
        }, main)

        local mark = panel({
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            Position = UDim2.new(0, 11, 0.5, -11),
            Size = UDim2.new(0, 22, 0, 22),
        }, header, 6)
        local markGradient = create("UIGradient", {
            Color = ColorSequence.new(PAL.accent, PAL.accentAlt),
            Rotation = 0,
        }, mark)
        tween(markGradient, TW.spin, { Rotation = 360 })
        label({
            Text = "R",
            Font = FONT.black,
            TextSize = 13,
            TextColor3 = PAL.shellBottom,
            TextXAlignment = Enum.TextXAlignment.Center,
            Size = UDim2.new(1, 0, 1, 0),
        }, mark)

        label({
            Text = "RIFTWARE",
            Font = FONT.bold,
            TextSize = 12,
            Position = UDim2.new(0, 40, 0, 6),
            Size = UDim2.new(1, -140, 0, 12),
        }, header)
        label({
            Text = "AutoRank v" .. VERSION,
            Font = FONT.med,
            TextSize = 9,
            TextColor3 = PAL.faint,
            Position = UDim2.new(0, 40, 0, 18),
            Size = UDim2.new(1, -140, 0, 10),
        }, header)

        buildSwitch(header)
        local minBtn = iconButton(header, -48, "\u{2013}", PAL.text)
        local closeBtn = iconButton(header, -26, "\u{00D7}", PAL.bad)
        return header, minBtn, closeBtn
    end

    local function buildRankCard(parent)
        local card = panel({ Size = UDim2.new(1, 0, 0, 76), LayoutOrder = 1 }, parent, 9)
        GUI.rankStroke = outline(card, PAL.line, 0.45)
        inset(card, 10, 10, 10, 10)

        label({
            Text = "CURRENT RANK",
            Font = FONT.bold,
            TextSize = 9,
            TextColor3 = PAL.faint,
            Size = UDim2.new(0.6, 0, 0, 10),
        }, card)

        GUI.flag = label({
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = PAL.warn,
            BackgroundTransparency = 0.85,
            Font = FONT.bold,
            Text = "",
            TextSize = 8,
            TextColor3 = PAL.warn,
            TextXAlignment = Enum.TextXAlignment.Center,
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, 0, 0, -1),
            Size = UDim2.new(0, 0, 0, 14),
            Visible = false,
        }, card)
        corner(GUI.flag, 4)
        inset(GUI.flag, 0, 6, 0, 6)

        GUI.rankNumber = label({
            Text = "\u{2013}",
            Font = FONT.black,
            TextSize = 22,
            Position = UDim2.new(0, 0, 0, 11),
            Size = UDim2.new(0, 44, 0, 26),
        }, card)
        GUI.rankTitle = label({
            Text = "connecting",
            Font = FONT.bold,
            TextSize = 13,
            Position = UDim2.new(0, 48, 0, 17),
            Size = UDim2.new(1, -48, 0, 16),
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, card)

        GUI.starText = label({
            Text = "0 / 0 stars",
            Font = FONT.med,
            TextSize = 10,
            TextColor3 = PAL.dim,
            Position = UDim2.new(0, 0, 0, 38),
            Size = UDim2.new(0.42, 0, 0, 11),
        }, card)
        GUI.rewardText = label({
            Text = "",
            Font = FONT.med,
            TextSize = 9,
            TextColor3 = PAL.faint,
            TextXAlignment = Enum.TextXAlignment.Right,
            Position = UDim2.new(0.42, 0, 0, 39),
            Size = UDim2.new(0.58, 0, 0, 10),
        }, card)

        local _, fill = bar(card, UDim2.new(0, 0, 0, 51), UDim2.new(1, 0, 0, 5), 3, true)
        GUI.starFill = fill
        return card
    end

    local function buildGoalRow(parent, index)
        local row = panel({
            BackgroundColor3 = PAL.raised,
            Size = UDim2.new(1, 0, 0, 34),
            Visible = false,
            LayoutOrder = index + 1,
        }, parent, 7)

        local badge = panel({
            BackgroundColor3 = PAL.accentAlt,
            BackgroundTransparency = 0.8,
            Position = UDim2.new(0, 8, 0, 6),
            Size = UDim2.new(0, 28, 0, 14),
        }, row, 4)
        local badgeText = label({
            Text = "",
            Font = FONT.bold,
            TextSize = 9,
            TextColor3 = PAL.accentAlt,
            TextXAlignment = Enum.TextXAlignment.Center,
            Size = UDim2.new(1, 0, 1, 0),
        }, badge)
        local title = label({
            Text = "",
            Font = FONT.med,
            TextSize = 11,
            Position = UDim2.new(0, 42, 0, 5),
            Size = UDim2.new(1, -110, 0, 13),
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, row)
        local value = label({
            Text = "",
            Font = FONT.bold,
            TextSize = 10,
            TextColor3 = PAL.dim,
            TextXAlignment = Enum.TextXAlignment.Right,
            Position = UDim2.new(1, -66, 0, 5),
            Size = UDim2.new(0, 58, 0, 13),
        }, row)
        local _, fill = bar(row, UDim2.new(0, 8, 0, 23), UDim2.new(1, -16, 0, 4), 2, false)

        return { frame = row, badge = badge, badgeText = badgeText, title = title, value = value, fill = fill, seen = -1 }
    end

    local function buildGoals(parent)
        local section = create("Frame", {
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 0),
            LayoutOrder = 2,
        }, parent)
        column(section, 5)
        GUI.goalCount = sectionCaption("RANK GOALS", section, 1)
        for i = 1, UI.rows do
            GUI.rows[i] = buildGoalRow(section, i)
        end
        GUI.goalEmpty = label({
            Text = "waiting for goal data",
            Font = FONT.med,
            TextSize = 10,
            TextColor3 = PAL.faint,
            Size = UDim2.new(1, 0, 0, 16),
            LayoutOrder = UI.rows + 2,
        }, section)
        return section
    end

    local function buildStatusCard(parent)
        local card = panel({
            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.new(1, 0, 0, 0),
            LayoutOrder = 3,
        }, parent, 7)
        outline(card, PAL.line, 0.55)

        GUI.statusStripe = panel({
            BackgroundColor3 = PAL.accent,
            Size = UDim2.new(0, 3, 1, 0),
        }, card, 2)

        local holder = create("Frame", {
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 0),
        }, card)
        inset(holder, 9, 10, 9, 13)

        GUI.statusDot = panel({
            BackgroundColor3 = PAL.accent,
            Position = UDim2.new(0, 0, 0, 3),
            Size = UDim2.new(0, 6, 0, 6),
        }, holder, 3)
        tween(GUI.statusDot, TW.pulse, { BackgroundTransparency = 0.6 })

        GUI.statusText = label({
            AutomaticSize = Enum.AutomaticSize.Y,
            Text = "starting",
            Font = FONT.med,
            TextSize = 10,
            TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top,
            Position = UDim2.new(0, 14, 0, 0),
            Size = UDim2.new(1, -14, 0, 12),
        }, holder)
        return card
    end

    local function buildStats(parent)
        local grid = create("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 38),
            LayoutOrder = 4,
        }, parent)
        create("UIGridLayout", {
            CellPadding = UDim2.new(0, 5, 0, 5),
            CellSize = UDim2.new(0.25, -4, 0, 38),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, grid)

        for i, def in ipairs(UI.chips) do
            local chip = panel({ BackgroundColor3 = PAL.raised, LayoutOrder = i }, grid, 7)
            local value = label({
                Text = "0",
                Font = FONT.bold,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Center,
                Position = UDim2.new(0, 0, 0, 6),
                Size = UDim2.new(1, 0, 0, 15),
            }, chip)
            label({
                Text = def.caption,
                Font = FONT.med,
                TextSize = 8,
                TextColor3 = PAL.faint,
                TextXAlignment = Enum.TextXAlignment.Center,
                Position = UDim2.new(0, 0, 0, 22),
                Size = UDim2.new(1, 0, 0, 9),
            }, chip)
            GUI.stats[def.key] = value
        end
        return grid
    end

    local function buildFooter(parent)
        local footer = create("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 26),
            LayoutOrder = 5,
        }, parent)
        local seam = create("Frame", {
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 1),
        }, footer)
        create("UIGradient", {
            Color = ColorSequence.new(PAL.accent, PAL.accentAlt),
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.55),
                NumberSequenceKeypoint.new(1, 0.9),
            }),
        }, seam)

        GUI.footerTarget = label({
            Text = "",
            Font = FONT.med,
            TextSize = 9,
            TextColor3 = PAL.dim,
            Position = UDim2.new(0, 0, 0, 6),
            Size = UDim2.new(0.66, 0, 0, 10),
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, footer)
        GUI.footerClock = label({
            Text = "00:00:00",
            Font = FONT.bold,
            TextSize = 9,
            TextColor3 = PAL.dim,
            TextXAlignment = Enum.TextXAlignment.Right,
            Position = UDim2.new(0.66, 0, 0, 6),
            Size = UDim2.new(0.34, 0, 0, 10),
        }, footer)
        GUI.footerFarm = label({
            Text = "",
            Font = FONT.body,
            TextSize = 9,
            TextColor3 = PAL.faint,
            Position = UDim2.new(0, 0, 0, 16),
            Size = UDim2.new(0.6, 0, 0, 9),
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, footer)
        label({
            Text = (CONFIG.GuiToggleKey and CONFIG.GuiToggleKey.Name or "none") .. " hides",
            Font = FONT.body,
            TextSize = 9,
            TextColor3 = PAL.faint,
            TextXAlignment = Enum.TextXAlignment.Right,
            Position = UDim2.new(0.4, 0, 0, 16),
            Size = UDim2.new(0.6, 0, 0, 9),
        }, footer)
        return footer
    end

    local function bindDrag(main, header)
        local dragging, origin, basePos = false, nil, nil
        track(header.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                origin = input.Position
                basePos = main.Position
            end
        end))
        track(UserInputService.InputChanged:Connect(function(input)
            if not (dragging and origin and basePos) then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                local delta = input.Position - origin
                main.Position = UDim2.new(basePos.X.Scale, basePos.X.Offset + delta.X, basePos.Y.Scale, basePos.Y.Offset + delta.Y)
            end
        end))
        track(UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end))
    end

    local function bindCollapse(body, minBtn)
        local collapsed, measured = false, 0
        track(minBtn.MouseButton1Click:Connect(function()
            collapsed = not collapsed
            if collapsed then
                measured = body.AbsoluteSize.Y
                if measured <= 0 then measured = 240 end
                body.AutomaticSize = Enum.AutomaticSize.None
                body.Size = UDim2.new(1, 0, 0, measured)
                minBtn.Text = "+"
                tween(body, TW.slide, { Size = UDim2.new(1, 0, 0, 0) })
            else
                minBtn.Text = "\u{2013}"
                local anim = tween(body, TW.slide, { Size = UDim2.new(1, 0, 0, measured > 0 and measured or 240) })
                if anim then
                    anim.Completed:Connect(function()
                        if not collapsed then body.AutomaticSize = Enum.AutomaticSize.Y end
                    end)
                else
                    body.AutomaticSize = Enum.AutomaticSize.Y
                end
            end
        end))
    end

    function buildGui()
        if not CONFIG.ShowGui then return end
        local ok, err = pcall(function()
            local sg = Instance.new("ScreenGui")
            sg.Name = "RiftwareAutoRankGui"
            sg.ResetOnSpawn = false
            sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            sg.DisplayOrder = 999
            pcall(function()
                if syn and syn.protect_gui then syn.protect_gui(sg) end
            end)
            sg.Parent = guiParent()
            gui = sg

            local main = panel({
                Name = "Window",
                Active = true,
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                Position = UI.pos + UDim2.new(0, 0, 0, 12),
                Size = UDim2.new(0, GUI_WIDTH, 0, 0),
                ZIndex = 2,
            }, sg, 11)
            create("UIGradient", {
                Color = ColorSequence.new(PAL.shellTop, PAL.shellBottom),
                Rotation = 90,
            }, main)
            outline(main, PAL.line, 0.1)
            column(main, 0)
            GUI.main = main

            local shadow = create("ImageLabel", {
                Name = "Shadow",
                BackgroundTransparency = 1,
                Image = "rbxassetid://6014261993",
                ImageColor3 = Color3.fromRGB(0, 0, 0),
                ImageTransparency = 0.45,
                ScaleType = Enum.ScaleType.Slice,
                SliceCenter = Rect.new(49, 49, 450, 450),
                ZIndex = 0,
            }, sg)
            local function syncShadow()
                shadow.Position = main.Position - UDim2.new(0, UI.shadow, 0, UI.shadow)
                shadow.Size = UDim2.new(0, main.AbsoluteSize.X + UI.shadow * 2, 0, main.AbsoluteSize.Y + UI.shadow * 2)
            end
            pcall(function()
                track(main:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncShadow))
                track(main:GetPropertyChangedSignal("Position"):Connect(syncShadow))
            end)
            syncShadow()

            local header, minBtn, closeBtn = buildHeader(main)

            local rule = create("Frame", {
                Name = "Rule",
                BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                BorderSizePixel = 0,
                Size = UDim2.new(0, 0, 0, 2),
                LayoutOrder = 2,
            }, main)
            sweep(create("UIGradient", {
                Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, PAL.accent),
                    ColorSequenceKeypoint.new(0.5, PAL.accentAlt),
                    ColorSequenceKeypoint.new(1, PAL.accent),
                }),
                Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.8),
                    NumberSequenceKeypoint.new(0.5, 0),
                    NumberSequenceKeypoint.new(1, 0.8),
                }),
            }, rule))
            tween(rule, TW.bar, { Size = UDim2.new(1, 0, 0, 2) })

            local body = create("Frame", {
                Name = "Body",
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                ClipsDescendants = true,
                Size = UDim2.new(1, 0, 0, 0),
                LayoutOrder = 3,
            }, main)
            inset(body, 10, 10, 10, 10)
            column(body, 7)

            buildRankCard(body)
            buildGoals(body)
            buildStatusCard(body)
            buildStats(body)
            buildFooter(body)

            bindDrag(main, header)
            bindCollapse(body, minBtn)
            track(closeBtn.MouseButton1Click:Connect(Stop))
            track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
                if gameProcessed then return end
                if input.KeyCode == CONFIG.GuiToggleKey and gui then
                    gui.Enabled = not gui.Enabled
                end
            end))
            paintSwitch(state.enabled == true)
            tween(main, TW.slide, { Position = UI.pos })
        end)
        if ok then
            log("GUI created (toggle: %s)", tostring(CONFIG.GuiToggleKey and CONFIG.GuiToggleKey.Name or "none"))
        else
            warnlog("gui", "GUI creation failed: %s", tostring(err))
        end
    end

    local function setFlag(text, color)
        local flag = GUI.flag
        if not flag then return end
        if not text then
            flag.Visible = false
            GUI.flagText = nil
            return
        end
        if GUI.flagText ~= text then
            GUI.flagText = text
            flag.Text = text
            flag.TextColor3 = color
            flag.BackgroundColor3 = color
            flag.Visible = true
            flash(flag, "BackgroundTransparency", 0.45, 0.85)
        end
    end

    local function refreshRank()
        local info = state.rank
        if not info then
            GUI.rankNumber.Text = "\u{2013}"
            GUI.rankTitle.Text = "waiting for save data"
            GUI.starText.Text = "0 / 0 stars"
            GUI.rewardText.Text = ""
            setBar(GUI.starFill, 0)
            setFlag(nil)
            return
        end
        local stars = tonumber(info.stars) or 0
        local total = tonumber(info.totalStars) or 0
        if GUI.shown.rank ~= info.rankNumber then
            if GUI.shown.rank ~= nil then
                flash(GUI.rankNumber, "TextColor3", PAL.accent, PAL.text)
                flash(GUI.rankStroke, "Color", PAL.accent, PAL.line)
            end
            GUI.shown.rank = info.rankNumber
        end
        GUI.rankNumber.Text = int(info.rankNumber)
        GUI.rankTitle.Text = tostring(info.title)
        GUI.starText.Text = string.format("%s / %s stars", shortNum(stars), shortNum(total))
        setBar(GUI.starFill, total > 0 and stars / total or (info.isMax and 1 or 0))

        local rewards = string.format("rewards %s/%s", int(info.redeemedCount), int(#info.rewards))
        local nextIn = nextRewardIn(info)
        if nextIn then
            rewards = rewards .. string.format("  \u{00B7}  next in %s", shortNum(nextIn))
        elseif info.allRedeemed then
            rewards = rewards .. "  \u{00B7}  all claimed"
        end
        GUI.rewardText.Text = rewards

        if not state.enabled then
            setFlag("PAUSED", PAL.warn)
        elseif info.isMax then
            setFlag("MAX RANK", PAL.accent)
        elseif state.worldSwitching then
            setFlag("TELEPORTING", PAL.accentAlt)
        elseif state.worldMismatch then
            setFlag("WRONG WORLD", PAL.bad)
        elseif info.blockedByZone then
            setFlag("NEEDS ZONE " .. tostring(info.zoneNumberNeeded or "?"), PAL.warn)
        elseif info.blockedByRebirth then
            setFlag("NEEDS " .. tostring(info.rebirthsNeeded or "?") .. " REBIRTHS", PAL.warn)
        else
            setFlag(nil)
        end
    end

    local function refreshGoals()
        local goals = state.goals or {}
        local manual = 0
        for i = 1, UI.rows do
            local row = GUI.rows[i]
            local goal = goals[i]
            if not goal then
                row.frame.Visible = false
                row.seen = -1
            else
                local amount = tonumber(goal.Amount) or 0
                local progress = tonumber(goal.Progress) or 0
                local done = amount > 0 and progress >= amount
                local tint = PAL.accentAlt
                if done then
                    tint = PAL.accent
                elseif not goal.supported then
                    tint = PAL.bad
                    manual += 1
                end
                if not row.frame.Visible then
                    row.frame.Visible = true
                    flash(row.frame, "BackgroundTransparency", 1, 0, TW.slide)
                end
                row.badge.BackgroundColor3 = tint
                row.badgeText.TextColor3 = tint
                row.badgeText.Text = done and "DONE" or ("+" .. int(goal.Stars))
                row.title.Text = tostring(goal.title) .. (goal.supported and "" or "  (manual)")
                row.title.TextColor3 = goal.supported and PAL.text or PAL.dim
                row.value.Text = string.format("%s / %s", shortNum(progress), shortNum(amount))
                row.value.TextColor3 = done and PAL.accent or PAL.dim
                setBar(row.fill, amount > 0 and progress / amount or 0, tint)
                if row.seen >= 0 and progress > row.seen then
                    flash(row.frame, "BackgroundColor3", tint:Lerp(PAL.raised, 0.78), PAL.raised)
                end
                row.seen = progress
            end
        end
        local shown = math.min(#goals, UI.rows)
        GUI.goalEmpty.Visible = shown == 0
        if shown == 0 then
            GUI.goalCount.Text = ""
        elseif manual > 0 then
            GUI.goalCount.Text = string.format("%s TRACKED  \u{00B7}  %s MANUAL", int(shown), int(manual))
        else
            GUI.goalCount.Text = string.format("%s TRACKED", int(shown))
        end
    end

    local function refreshStatus()
        local color = PAL.accent
        if not state.alive then
            color = PAL.bad
        elseif not state.enabled then
            color = PAL.warn
        elseif state.worldMismatch then
            color = PAL.bad
        elseif state.worldSwitching or state.hopping then
            color = PAL.accentAlt
        end
        if GUI.shown.status ~= color then
            GUI.shown.status = color
            tween(GUI.statusDot, TW.fast, { BackgroundColor3 = color })
            tween(GUI.statusStripe, TW.fast, { BackgroundColor3 = color })
        end
        GUI.statusText.Text = tostring(state.action)
        paintSwitch(state.enabled == true)
    end

    local function refreshFooter()
        local counters = state.counters
        for key, value in pairs(GUI.stats) do
            local text = shortNum(counters[key] or 0)
            if value.Text ~= text then
                value.Text = text
                flash(value, "TextColor3", PAL.accent, PAL.text)
            end
        end
        local zone = cache.zone
        local zoneName = (zone and (zone.ZoneName or zone._id)) or cache.zoneId or "?"
        local egg = cache.egg
        local eggText = egg and string.format("%s x%s", tostring(egg.name or egg.id), int(cache.maxHatch or 1)) or "no egg"
        GUI.footerTarget.Text = string.format("%s  \u{00B7}  world %s  \u{00B7}  %s",
            tostring(zoneName), tostring(state.world or "?"), eggText)
        GUI.footerFarm.Text = string.format("%s pets  \u{00B7}  %s targets  \u{00B7}  %s events",
            int(state.farmPets), int(state.farmTargets), int(counters.eventTargets))
        GUI.footerClock.Text = formatTime(os.clock() - state.startedAt)
    end

    function refreshGui()
        if not gui or not GUI.main or not gui.Parent then return end
        refreshRank()
        refreshGoals()
        refreshStatus()
        refreshFooter()
    end
end

local function spawnLoop(name, tickFn, intervalFn)
    task.spawn(function()
        while state.alive do
            local ok, err = pcall(tickFn)
            if not ok then
                warnlog("loop-" .. name, "%s loop error: %s", name, tostring(err))
                task.wait(1)
            end
            if not state.alive then break end
            local okI, iv = pcall(intervalFn)
            iv = okI and tonumber(iv) or 1
            task.wait(math.max(0.05, iv))
        end
    end)
end

local function farmInterval()
    if not CONFIG.AutoFarm or not state.enabled or state.worldSwitching or state.worldMismatch then return 1 end
    return CONFIG.FarmTick
end

local function hatchInterval()
    local now = os.clock()
    if hatchBackoffUntil > now then return math.min(5, hatchBackoffUntil - now) end
    if not hatchPlanned() or state.worldSwitching or state.worldMismatch then return 1 end
    return CONFIG.HatchDelay
end

local function startThreads()
    spawnLoop("controller", controllerTick, function() return CONFIG.ControllerTick end)
    spawnLoop("farm", farmTick, farmInterval)
    spawnLoop("hatch", hatchTick, hatchInterval)
    spawnLoop("craft", craftTick, function() return CONFIG.CraftTick end)
    spawnLoop("events", eventTick, function() return CONFIG.EventTick end)
    spawnLoop("gui", refreshGui, function() return 0.5 end)
    spawnLoop("persist", writeStateFile, function() return 60 end)
    installBreakableListener()
end

local function bootstrap()
    repeat task.wait() until game:IsLoaded() or not state.alive
    if not state.alive then return false end
    local t0 = os.clock()
    while state.alive and not Players.LocalPlayer do
        if os.clock() - t0 > 60 then
            warn(TAG .. "LocalPlayer not available after 60 s - aborting")
            return false
        end
        task.wait(0.5)
    end
    if not state.alive then return false end
    LocalPlayer = Players.LocalPlayer
    t0 = os.clock()
    while state.alive do
        local lib = RS:FindFirstChild("Library")
        local client = lib and lib:FindFirstChild("Client")
        if client then break end
        if os.clock() - t0 > 60 then
            warn(TAG .. "ReplicatedStorage.Library.Client not found after 60 s - aborting")
            return false
        end
        logEvery("boot-lib", 5, "Waiting for ReplicatedStorage.Library.Client...")
        task.wait(0.5)
    end
    if not state.alive then return false end
    loadModules()
    if not (G.Save and G.Network) then
        warn(TAG .. "Save/Network module unavailable - cannot continue")
        return false
    end
    t0 = os.clock()
    while state.alive and getSave() == nil do
        if os.clock() - t0 > 60 then
            warn(TAG .. "Save.Get() stayed nil for 60 s - aborting")
            return false
        end
        logEvery("boot-save", 5, "Waiting for save data...")
        task.wait(0.5)
    end
    t0 = os.clock()
    while state.alive and os.clock() - t0 < 5 do
        local ok, loaded = pcall(function() return LocalPlayer:GetAttribute("__LOADED") end)
        if ok and loaded then break end
        task.wait(0.25)
    end
    return state.alive
end

local function startupSummary()
    local info = state.rank
    if info then
        log("Rank %s - %s | %s/%s stars | rewards %s/%s | rebirths %s", int(info.rankNumber), tostring(info.title), int(info.stars),
            int(info.totalStars), int(info.redeemedCount), int(#info.rewards), int(info.rebirths))
    end
    for _, g in ipairs(state.goals) do
        log("  goal [%s*] %s  %s/%s (type %s)%s", int(g.Stars), tostring(g.title), int(g.Progress), int(g.Amount), tostring(g.Type),
            g.supported and "" or " (manual)")
    end
    local zone = bestZone()
    local egg = bestEgg()
    log("Best zone: %s (world %s) | best egg: %s (#%s, max hatch %s) | current world: %s",
        tostring(bestZoneName()), tostring(zone and zone.WorldNumber or "?"),
        tostring(egg and (egg.name or egg.id) or "?"), tostring(egg and egg.number or "?"), int(maxHatch()),
        tostring(currentWorld() or "?"))
    if state.action ~= "" then log("Action: %s", state.action) end
end

local function main()
    log("Riftware AutoRank v%s starting (identity %s)", VERSION, tostring(type(getthreadidentity) == "function" and getthreadidentity() or "?"))
    if not bootstrap() then
        Stop()
        return
    end
    restoreStateFile()
    installPatches()
    pcall(installAntiAfk)
    queueSelf(false)
    buildGui()
    local ok, err = pcall(controllerTick)
    if not ok then warnlog("first-tick", "first controller tick failed: %s", tostring(err)) end
    startThreads()
    pcall(startupSummary)
    log("All threads running. Toggle automation with the panel switch or getgenv().RiftwareAutoRank.SetEnabled(true/false); stop with .Stop()")
end

task.spawn(function()
    local ok, err = pcall(main)
    if not ok then
        warn(TAG .. "fatal error during startup: " .. tostring(err))
        Stop()
    end
end)
