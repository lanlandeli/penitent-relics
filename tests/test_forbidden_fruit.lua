-- Offline regression tests for the rewritten Forbidden Fruit state machine.

CacheFlag = { CACHE_DAMAGE = 1 }
LevelStage = { STAGE8 = 13 }
GridRooms = { ROOM_GENESIS_IDX = -12, ROOM_DUNGEON_IDX = -4 }
PickupPrice = { PRICE_ONE_HEART = -1 }
PlayerType = { PLAYER_KEEPER = 14, PLAYER_KEEPER_B = 33 }
PickupVariant = { PICKUP_COLLECTIBLE = 100 }
EntityType = { ENTITY_PICKUP = 5 }
EntityType.ENTITY_EFFECT = 1000
EntityCollisionClass = { ENTCOLL_NONE = 0 }
GridCollisionClass = { COLLISION_NONE = 0 }
ActiveSlot = { SLOT_PRIMARY = 0, SLOT_SECONDARY = 1 }
CollectibleType = {
    COLLECTIBLE_MOVING_BOX = 477,
    COLLECTIBLE_ABYSS = 706,
    COLLECTIBLE_VOID = 523,
}

local qualities = { [101] = 0, [102] = 1, [103] = 2, [104] = 3, [105] = 4 }
Isaac = {
    DebugString = function() end,
    GetItemConfig = function()
        return {
            GetCollectible = function(_, id)
                return qualities[id] ~= nil and { Quality = qualities[id] } or nil
            end,
        }
    end,
}
GetPtrHash = function(entity) return entity.hash or entity.InitSeed or 1 end
EntityPtr = function(entity) return { Ref = entity } end

local module = dofile("mod/modules/forbidden_fruit/init.lua")
module.manager = {
    getConfig = function(_, _, _, fallback) return fallback end,
    mod = {},
    Util = {
        warn = function() end,
        safeCall = function(fn) fn() end,
    },
}

local expected = { 1.0, 0.9, 0.8, 0.7, 0.6 }
for quality = 0, 4 do
    assert(module:damageMultiplier(quality) == expected[quality + 1],
        "incorrect quality multiplier")
end

local playerData = {}
local player = {
    hash = 90,
    Damage = 10,
    Exists = function() return true end,
    GetData = function() return playerData end,
    AddCacheFlags = function(_, flag) assert(flag == CacheFlag.CACHE_DAMAGE) end,
    EvaluateItems = function() end,
    GetPlayerType = function() return 0 end,
}
for itemId = 101, 105 do
    playerData = {}
    player.Damage = 10
    local applied, quality = module:applyPenalty(player, itemId)
    assert(applied and quality == qualities[itemId], "penalty was not applied")
    module:onEvaluateCache(player, CacheFlag.CACHE_DAMAGE)
    assert(math.abs(player.Damage - 10 * expected[quality + 1]) < 0.0001,
        "damage cache multiplier was incorrect")
    assert(module:applyPenalty(player, itemId) == false,
        "penalty was applied twice")
end
module:clearPlayerPenalty(player)
assert(playerData.pr_forbidden_fruit_active == nil,
    "floor cleanup retained the penalty")

local normalDeal = {}
module:configureDeal(normalDeal, player)
assert(normalDeal.ShopItemId == -2
        and normalDeal.Price == PickupPrice.PRICE_ONE_HEART
        and normalDeal.AutoUpdatePrice == false,
    "normal deal configuration was incorrect")
local keeperDeal = {}
module:configureDeal(keeperDeal, {
    GetPlayerType = function() return PlayerType.PLAYER_KEEPER end,
})
assert(keeperDeal.Price == 15, "Keeper deal price was incorrect")

local pickupData = {
    pr_forbidden_fruit_option = true,
    pr_forbidden_fruit_group = 77,
}
local pickup = {
    hash = 501,
    Type = EntityType.ENTITY_PICKUP,
    Variant = PickupVariant.PICKUP_COLLECTIBLE,
    SubType = 104,
    InitSeed = 501,
    OptionsPickupIndex = 77,
    Exists = function() return true end,
    GetData = function() return pickupData end,
}
module.floorState = {
    spawned = true,
    resolved = false,
    declined = false,
    optionGroup = 77,
    optionPtrs = { EntityPtr(pickup) },
    optionSeeds = { [501] = true },
}
module.initializing = false
module.isStartingRoom = function() return true end
Game = function()
    return { GetFrameCount = function() return 20 end }
end
local collider = { ToPlayer = function() return player end }
module:onPrePickupCollision(pickup, collider)
assert(module.pendingPick and module.pendingPick.itemId == 104,
    "marked pedestal collision did not arm the transaction")

local resolved = false
module.resolve = function(_, resolvedPlayer, itemId)
    resolved = resolvedPlayer == player and itemId == 104
    module.floorState.resolved = resolved
    module.pendingPick = nil
    return resolved
end
module:onEntityRemove({
    hash = 999,
    Type = EntityType.ENTITY_PICKUP,
    Variant = PickupVariant.PICKUP_COLLECTIBLE,
    InitSeed = 999,
})
assert(not resolved and module.pendingPick,
    "unrelated starting-room pedestal removal resolved the offer")
module:onEntityRemove(pickup)
assert(resolved and module.pendingPick == nil,
    "the armed pedestal's native removal did not resolve the offer")

resolved = false
module.floorState.resolved = false
module.floorState.declined = false
module.pendingPick = nil
module.initializing = true
module:onPrePickupCollision(pickup, collider)
assert(module.pendingPick == nil, "initialization reentry armed a transaction")
module.initializing = false

local swappedData = {
    pr_forbidden_fruit_option = true,
    pr_forbidden_fruit_group = 77,
}
local swappedPickup = {
    hash = 502,
    Type = EntityType.ENTITY_PICKUP,
    Variant = PickupVariant.PICKUP_COLLECTIBLE,
    SubType = 50,
    InitSeed = 502,
    OptionsPickupIndex = 77,
    ShopItemId = -2,
    Price = -1,
    AutoUpdatePrice = false,
    Exists = function() return true end,
    GetData = function() return swappedData end,
}
module.floorState.optionSeeds[502] = true
module.pendingPick = {
    player = EntityPtr(player), itemId = 105, seed = 502, hash = 502, frame = 20,
}
local preserved
module.resolve = function(_, resolvedPlayer, itemId, kept)
    resolved = resolvedPlayer == player and itemId == 105
    preserved = kept
    return resolved
end
module:onPickupUpdate(swappedPickup)
assert(resolved and preserved == swappedPickup,
    "active-item pedestal transformation did not resolve")
assert(swappedPickup.Price == 0 and swappedPickup.ShopItemId == -1
        and swappedPickup.OptionsPickupIndex == 0,
    "swapped-out active remained a paid option")

local removed = false
module.floorState = {
    spawned = true,
    resolved = false,
    declined = false,
    optionGroup = 77,
    optionPtrs = { { Ref = {
        hash = 600,
        Exists = function() return true end,
        Remove = function() removed = true end,
    } } },
    optionSeeds = { [600] = true },
}
module.pendingPick = { itemId = 104 }
module.saveState = function() end
assert(module:declineOffer() and removed and module.pendingPick == nil,
    "decline did not invalidate the offer before removing it")

local grants = 0
local testPlayer = {
    HasCollectible = function() return grants > 0 end,
    AddCollectible = function() grants = grants + 1 end,
}
module.itemId = 735
module.manager.getConfig = function(_, _, key, fallback)
    if key == "grantOnNewGame" then return true end
    return fallback
end
Isaac.GetPlayer = function() return testPlayer end
assert(module:grantTestItem(false) and grants == 1,
    "test item was not granted once")
assert(not module:grantTestItem(false) and grants == 1,
    "test item was granted twice")

local vectorMeta = {
    __add = function(a, b) return setmetatable({ X = a.X + b.X, Y = a.Y + b.Y }, vectorMeta) end,
}
Vector = setmetatable({}, {
    __call = function(_, x, y)
        return setmetatable({ X = x, Y = y }, vectorMeta)
    end,
})
Vector.Zero = Vector(0, 0)
local visualSprite = {}
local visualRemoved = false
local visual = {
    Position = Vector(0, 0),
    Velocity = Vector.Zero,
    Exists = function() return not visualRemoved end,
    ToEffect = function(self) return self end,
    SetTimeout = function(self, timeout) self.timeout = timeout end,
    SetShadowSize = function(self, size) self.shadowSize = size end,
    GetSprite = function() return visualSprite end,
    Remove = function() visualRemoved = true end,
}
visualSprite.Load = function(_, filename) visualSprite.filename = filename end
visualSprite.Play = function(_, animation) visualSprite.animation = animation end
Isaac.Spawn = function(entityType, variant, subtype, position)
    assert(entityType == EntityType.ENTITY_EFFECT and variant == 777 and subtype == 3)
    visual.Position = position
    return visual
end
local visualData = {
    pr_forbidden_fruit_active = true,
    pr_forbidden_fruit_quality = 3,
}
local visualPlayer = {
    hash = 92,
    Position = Vector(100, 120),
    DepthOffset = 2,
    GetData = function() return visualData end,
    IsDead = function() return false end,
}
module.visualVariant = 777
module.debuffVisuals = {}
module.eachPlayer = function(_, fn) fn(visualPlayer, 0) end
module:updateDebuffVisuals()
assert(module.debuffVisuals[92] and visualSprite.animation == "Q3"
        and visualSprite.filename == "gfx/effects/forbidden_fruit_debuff.anm2",
    "debuff visual did not use the quality-specific animation")
assert(visual.timeout == -1 and visual.shadowSize == 0
        and visual.EntityCollisionClass == EntityCollisionClass.ENTCOLL_NONE
        and visual.GridCollisionClass == GridCollisionClass.COLLISION_NONE,
    "debuff visual retained native lifetime or collision")
assert(visual.Position.X == 100 and visual.Position.Y == 82
        and visual.DepthOffset == 47,
    "debuff visual did not follow above the player")
visualData.pr_forbidden_fruit_active = nil
module:updateDebuffVisuals()
assert(visualRemoved and module.debuffVisuals[92] == nil,
    "inactive penalty retained its debuff visual")

assert(module.onRender == nil and module.onPlayerUpdate == nil
        and module.checkPendingPicks == nil and module.spawnDebuffMark == nil
        and module.spawnOfferVisuals == nil,
    "removed animation/polling lifecycle remained in the rewritten module")

print("Forbidden Fruit regression tests passed.")
