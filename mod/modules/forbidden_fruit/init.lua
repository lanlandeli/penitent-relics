-- Forbidden Fruit
-- A floor-local paid choice implemented as one small entity-driven state
-- machine. Custom selection/debuff visuals are intentionally not loaded here.

local M = {
    id = "forbidden_fruit",
    name = "Forbidden Fruit",
    version = "3.1.0",
    description = "Choose one of two tempting items each floor, then bear its price.",
    category = "world",
    config = {
        q0DamageMult = 1.00,
        q1DamageMult = 0.90,
        q2DamageMult = 0.80,
        q3DamageMult = 0.70,
        q4DamageMult = 0.60,
        optionSpacing = 72,
        spawnDelayFrames = 1,
        debuffVisualEnabled = true,
        debuffVisualHeight = 38,
        grantOnNewGame = false,
    },
}

local ITEM_NAME = "Forbidden Fruit"
local VISUAL_NAME = "Penitent Relics Forbidden Fruit Debuff"
local DEBUFF_ANM2 = "gfx/effects/forbidden_fruit_debuff.anm2"
local KEY_ACTIVE = "pr_forbidden_fruit_active"
local KEY_QUALITY = "pr_forbidden_fruit_quality"
local KEY_MULT = "pr_forbidden_fruit_damage_mult"
local KEY_OPTION = "pr_forbidden_fruit_option"
local KEY_GROUP = "pr_forbidden_fruit_group"
local ONE_HEART_PRICE = PickupPrice.PRICE_ONE_HEART
local KEEPER_COIN_PRICE = 15
local PENDING_TIMEOUT = 3

local QUALITY_KEYS = {
    "q0DamageMult", "q1DamageMult", "q2DamageMult",
    "q3DamageMult", "q4DamageMult",
}

local function validEntity(entity)
    return entity and entity:Exists()
end

function M:cfg(key, fallback)
    return self.manager:getConfig(self, key, fallback)
end

function M:eachPlayer(fn)
    local game = Game()
    for index = 0, game:GetNumPlayers() - 1 do
        fn(Isaac.GetPlayer(index), index)
    end
end

function M:anyLivingHolder()
    local found = false
    self:eachPlayer(function(player)
        if not player:IsDead() and player:HasCollectible(self.itemId) then
            found = true
        end
    end)
    return found
end

function M:floorKey()
    local level = Game():GetLevel()
    return table.concat({
        tostring(level:GetStage()),
        tostring(level:GetStageType()),
        tostring(level:GetDungeonPlacementSeed()),
    }, ":")
end

function M:isStartingRoom()
    local level = Game():GetLevel()
    return level:GetCurrentRoomIndex() == level:GetStartingRoomIndex()
end

function M:isSupportedFloor()
    local game = Game()
    local level = game:GetLevel()
    if game:IsGreedMode() or level:IsAscent()
        or level:GetStage() == LevelStage.STAGE8 then
        return false
    end
    local roomIndex = level:GetCurrentRoomIndex()
    return roomIndex ~= GridRooms.ROOM_GENESIS_IDX
        and roomIndex ~= GridRooms.ROOM_DUNGEON_IDX
end

function M:newFloorState()
    self.floorState = {
        key = self:floorKey(),
        pendingSpawn = false,
        spawnFrame = -1,
        spawned = false,
        resolved = false,
        declined = false,
        optionGroup = 0,
        optionPtrs = {},
        optionSeeds = {},
        restoredItems = nil,
    }
    self.pendingPick = nil
end

function M:damageMultiplier(quality)
    local clamped = math.max(0, math.min(4, tonumber(quality) or 0))
    return self:cfg(QUALITY_KEYS[clamped + 1], 1.0 - clamped * 0.1)
end

function M:itemQuality(itemId)
    local item = Isaac.GetItemConfig():GetCollectible(itemId)
    if not item then
        return 0
    end
    return math.max(0, math.min(4, item.Quality or 0))
end

function M:refreshDamage(player)
    player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
    player:EvaluateItems()
end

function M:removeDebuffVisual(player)
    if not self.debuffVisuals then
        return
    end
    local hash = player and GetPtrHash(player) or nil
    local entry = hash and self.debuffVisuals[hash] or nil
    local visual = entry and entry.ptr and entry.ptr.Ref or nil
    if validEntity(visual) then
        visual:Remove()
    end
    if hash then
        self.debuffVisuals[hash] = nil
    end
end

function M:clearDebuffVisuals()
    for hash, entry in pairs(self.debuffVisuals or {}) do
        local visual = entry.ptr and entry.ptr.Ref or nil
        if validEntity(visual) then
            visual:Remove()
        end
        self.debuffVisuals[hash] = nil
    end
end

function M:spawnDebuffVisual(player, quality)
    if not self:cfg("debuffVisualEnabled", true) or not self.visualVariant then
        return nil
    end
    local height = self:cfg("debuffVisualHeight", 38)
    local visual = Isaac.Spawn(
        EntityType.ENTITY_EFFECT, self.visualVariant, quality,
        player.Position + Vector(0, -height), Vector.Zero, player
    ):ToEffect()
    if not visual then
        self.manager.Util.warn("Forbidden Fruit failed to spawn debuff visual")
        return nil
    end
    visual.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    visual.GridCollisionClass = GridCollisionClass.COLLISION_NONE
    visual:SetTimeout(-1)
    visual:SetShadowSize(0)
    visual.DepthOffset = (player.DepthOffset or 0) + 45
    local sprite = visual:GetSprite()
    sprite:Load(DEBUFF_ANM2, true)
    sprite:Play("Q" .. tostring(quality), true)
    return visual
end

function M:updateDebuffVisuals()
    local active = {}
    self:eachPlayer(function(player)
        local data = player:GetData()
        local hash = GetPtrHash(player)
        if data[KEY_ACTIVE] and not player:IsDead() then
            active[hash] = true
            local quality = math.max(0, math.min(4, data[KEY_QUALITY] or 0))
            local entry = self.debuffVisuals[hash]
            local visual = entry and entry.ptr and entry.ptr.Ref or nil
            if not validEntity(visual) then
                visual = self:spawnDebuffVisual(player, quality)
                if visual then
                    entry = { ptr = EntityPtr(visual), quality = quality }
                    self.debuffVisuals[hash] = entry
                end
            end
            if validEntity(visual) then
                local height = self:cfg("debuffVisualHeight", 38)
                visual.Position = player.Position + Vector(0, -height)
                visual.Velocity = Vector.Zero
                visual.DepthOffset = (player.DepthOffset or 0) + 45
                if entry and entry.quality ~= quality then
                    visual:GetSprite():Play("Q" .. tostring(quality), true)
                    entry.quality = quality
                end
            end
        end
    end)
    for hash, entry in pairs(self.debuffVisuals) do
        if not active[hash] then
            local visual = entry.ptr and entry.ptr.Ref or nil
            if validEntity(visual) then visual:Remove() end
            self.debuffVisuals[hash] = nil
        end
    end
end

function M:applyPenalty(player, itemId)
    local data = player:GetData()
    if data[KEY_ACTIVE] then
        return false
    end
    local quality = self:itemQuality(itemId)
    local multiplier = self:damageMultiplier(quality)
    data[KEY_ACTIVE] = true
    data[KEY_QUALITY] = quality
    data[KEY_MULT] = multiplier
    self:refreshDamage(player)
    Isaac.DebugString("[PenitentRelics] Forbidden Fruit penalty applied: item="
        .. tostring(itemId) .. " quality=" .. tostring(quality)
        .. " multiplier=" .. tostring(multiplier)
        .. " damage=" .. tostring(player.Damage))
    return true, quality
end

function M:clearPlayerPenalty(player)
    local data = player:GetData()
    local changed = data[KEY_ACTIVE] == true
    data[KEY_ACTIVE] = nil
    data[KEY_QUALITY] = nil
    data[KEY_MULT] = nil
    self:removeDebuffVisual(player)
    if changed then
        self:refreshDamage(player)
    end
end

function M:clearAllPenalties()
    self:eachPlayer(function(player)
        self:clearPlayerPenalty(player)
    end)
end

function M:onEvaluateCache(player, cacheFlag)
    if cacheFlag ~= CacheFlag.CACHE_DAMAGE then
        return
    end
    local data = player:GetData()
    if data[KEY_ACTIVE] then
        player.Damage = player.Damage * (data[KEY_MULT] or 1.0)
    end
end

function M:isKeeper(player)
    if not player or type(player.GetPlayerType) ~= "function" then
        return false
    end
    local playerType = player:GetPlayerType()
    return playerType == PlayerType.PLAYER_KEEPER
        or playerType == PlayerType.PLAYER_KEEPER_B
end

function M:configureDeal(pickup, player)
    pickup.ShopItemId = -2
    pickup.Price = self:isKeeper(player) and KEEPER_COIN_PRICE or ONE_HEART_PRICE
    pickup.AutoUpdatePrice = false
end

function M:nextOptionGroup()
    local seed = Game():GetLevel():GetDungeonPlacementSeed()
    return math.abs(seed % 2147483000) + 1
end

function M:optionPositions(room)
    local center = room:GetCenterPos()
    local half = self:cfg("optionSpacing", 72) * 0.5
    local left = room:FindFreePickupSpawnPosition(center + Vector(-half, 0), 0, true, false)
    local right = room:FindFreePickupSpawnPosition(center + Vector(half, 0), 0, true, false)
    if left:Distance(right) < 36 then
        left = room:FindFreePickupSpawnPosition(center + Vector(0, -half), 0, true, false)
        right = room:FindFreePickupSpawnPosition(center + Vector(0, half), 0, true, false)
    end
    if left:Distance(right) < 36 then
        return nil
    end
    return left, right
end

function M:markOption(pickup)
    local state = self.floorState
    local data = pickup:GetData()
    data[KEY_OPTION] = true
    data[KEY_GROUP] = state.optionGroup
    pickup.OptionsPickupIndex = state.optionGroup
    self:configureDeal(pickup, Isaac.GetPlayer(0))
    state.optionPtrs[#state.optionPtrs + 1] = EntityPtr(pickup)
    state.optionSeeds[pickup.InitSeed] = true
end

function M:isOurOption(pickup)
    local state = self.floorState
    if not pickup or pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE
        or not state or state.resolved or state.declined then
        return false
    end
    local data = pickup:GetData()
    return data[KEY_OPTION] == true
        or pickup.OptionsPickupIndex == state.optionGroup
        or state.optionSeeds[pickup.InitSeed] == true
end

function M:releaseSwappedActive(pickup)
    if not validEntity(pickup) then
        return nil
    end
    local data = pickup:GetData()
    data[KEY_OPTION] = nil
    data[KEY_GROUP] = nil
    pickup.OptionsPickupIndex = 0
    pickup.ShopItemId = -1
    pickup.Price = 0
    pickup.AutoUpdatePrice = false
    self.floorState.optionSeeds[pickup.InitSeed] = nil
    return pickup
end

function M:removeOptions(preservedPickup)
    local state = self.floorState
    if not state then
        return
    end
    local preservedHash = preservedPickup and GetPtrHash(preservedPickup) or nil
    for _, ptr in ipairs(state.optionPtrs) do
        local pickup = ptr.Ref
        if validEntity(pickup)
            and (not preservedHash or GetPtrHash(pickup) ~= preservedHash) then
            pickup:Remove()
        end
    end
    state.optionPtrs = {}
    state.optionSeeds = {}
end

function M:removeMatchingRoomOptions()
    local state = self.floorState
    if not state or state.optionGroup == 0 then
        return
    end
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local pickup = entity:ToPickup()
        if pickup and pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE
            and pickup.OptionsPickupIndex == state.optionGroup then
            pickup:Remove()
        end
    end
end

function M:spawnOptions()
    local state = self.floorState
    if not state or state.spawned or state.resolved or state.declined
        or not state.pendingSpawn or not self:isStartingRoom() then
        return false
    end
    state.pendingSpawn = false
    state.spawned = true
    state.optionGroup = state.optionGroup ~= 0
        and state.optionGroup or self:nextOptionGroup()
    self:removeMatchingRoomOptions()

    local room = Game():GetRoom()
    local left, right = self:optionPositions(room)
    if not left or not right then
        state.declined = true
        return false
    end
    local first, second
    if state.restoredItems then
        first, second = state.restoredItems[1], state.restoredItems[2]
        state.restoredItems = nil
    else
        local pool = Game():GetItemPool()
        local seed = Game():GetLevel():GetDungeonPlacementSeed()
        first = pool:GetCollectible(ItemPoolType.POOL_TREASURE, true, seed)
        second = pool:GetCollectible(ItemPoolType.POOL_TREASURE, true, seed + 1)
    end
    local firstPickup = Isaac.Spawn(
        EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE,
        first, left, Vector.Zero, nil
    ):ToPickup()
    local secondPickup = Isaac.Spawn(
        EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE,
        second, right, Vector.Zero, nil
    ):ToPickup()
    if not firstPickup or not secondPickup then
        if firstPickup then firstPickup:Remove() end
        if secondPickup then secondPickup:Remove() end
        state.declined = true
        return false
    end
    self:markOption(firstPickup)
    self:markOption(secondPickup)
    self:saveState()
    return true
end

function M:trackRoomOptions()
    local state = self.floorState
    if not state or not state.spawned or state.resolved or state.declined then
        return
    end
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local pickup = entity:ToPickup()
        if pickup and pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE
            and pickup.OptionsPickupIndex == state.optionGroup then
            if not state.optionSeeds[pickup.InitSeed] then
                self:markOption(pickup)
            elseif pickup.Price == 0 then
                self:configureDeal(pickup, Isaac.GetPlayer(0))
            end
        end
    end
end

function M:declineOffer()
    local state = self.floorState
    if not state or state.resolved or state.declined then
        return false
    end
    state.declined = true
    state.pendingSpawn = false
    self.pendingPick = nil
    self:removeOptions()
    self:saveState()
    return true
end

function M:resolve(player, itemId, preservedPickup)
    local state = self.floorState
    if not validEntity(player) or not state or state.resolved or state.declined then
        return false
    end
    local applied, quality = self:applyPenalty(player, itemId)
    if not applied then
        return false
    end
    state.resolved = true
    state.pendingSpawn = false
    self.pendingPick = nil
    self:removeOptions(preservedPickup)
    Isaac.DebugString("[PenitentRelics] Forbidden Fruit accepted: item="
        .. tostring(itemId) .. " quality=" .. tostring(quality))
    self:saveState()
    return true
end

function M:onPrePickupCollision(pickup, collider)
    local player = collider and collider:ToPlayer()
    if self.initializing or not player or not self:isStartingRoom()
        or not self:isOurOption(pickup) then
        return nil
    end
    self.pendingPick = {
        player = EntityPtr(player),
        itemId = pickup.SubType,
        seed = pickup.InitSeed,
        hash = GetPtrHash(pickup),
        frame = Game():GetFrameCount(),
    }
    Isaac.DebugString("[PenitentRelics] Forbidden Fruit transaction armed: item="
        .. tostring(pickup.SubType) .. " seed=" .. tostring(pickup.InitSeed))
    return nil
end

function M:onEntityRemove(entity)
    local pending = self.pendingPick
    local state = self.floorState
    if not pending or not state or state.resolved or state.declined
        or entity.Type ~= EntityType.ENTITY_PICKUP
        or entity.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then
        return
    end
    if entity.InitSeed ~= pending.seed and GetPtrHash(entity) ~= pending.hash then
        return
    end
    local player = pending.player and pending.player.Ref or nil
    self:resolve(player, pending.itemId)
end

function M:onPickupUpdate(pickup)
    local pending = self.pendingPick
    local state = self.floorState
    if not pending or not state or state.resolved or state.declined then
        return
    end
    if pickup.InitSeed ~= pending.seed and GetPtrHash(pickup) ~= pending.hash then
        return
    end
    if pickup.SubType ~= pending.itemId then
        local player = pending.player and pending.player.Ref or nil
        local preserved = self:releaseSwappedActive(pickup)
        self:resolve(player, pending.itemId, preserved)
    end
end

function M:onUseItem(itemId)
    if itemId == CollectibleType.COLLECTIBLE_MOVING_BOX
        or itemId == CollectibleType.COLLECTIBLE_VOID
        or itemId == CollectibleType.COLLECTIBLE_ABYSS then
        local state = self.floorState
        if state and state.spawned and not state.resolved and not state.declined then
            self:declineOffer()
        end
    end
    return nil
end

function M:onUpdate()
    local state = self.floorState
    if not state then
        return
    end
    if self.pendingPick
        and Game():GetFrameCount() - self.pendingPick.frame > PENDING_TIMEOUT then
        self.pendingPick = nil
    end
    if state.pendingSpawn and Game():GetFrameCount() >= state.spawnFrame then
        self:spawnOptions()
    elseif state.spawned and not state.resolved and not state.declined then
        self:trackRoomOptions()
    end
    self.manager.Util.safeCall(function()
        self:updateDebuffVisuals()
    end, "debuffVisual(forbidden_fruit)")
end

function M:onNewRoom()
    local state = self.floorState
    if not state then
        return
    end
    if state.spawned and not state.resolved and not state.declined
        and not self:isStartingRoom() then
        self:declineOffer()
    elseif self:isStartingRoom() and (state.resolved or state.declined) then
        self:removeMatchingRoomOptions()
    end
end

function M:onNewLevel()
    if self.initializing then
        return
    end
    local currentKey = self:floorKey()
    if self.floorState and self.floorState.key == currentKey then
        return
    end
    self.pendingPick = nil
    self:removeOptions()
    self:clearAllPenalties()
    self:newFloorState()
    if self:isSupportedFloor() and self:anyLivingHolder() then
        self.floorState.pendingSpawn = true
        self.floorState.spawnFrame = Game():GetFrameCount()
            + self:cfg("spawnDelayFrames", 1)
    end
    self:saveState()
end

function M:currentOptionItems()
    local items = {}
    local state = self.floorState
    if not state then
        return items
    end
    for _, ptr in ipairs(state.optionPtrs) do
        local pickup = ptr.Ref
        if validEntity(pickup) and self:isOurOption(pickup) then
            items[#items + 1] = pickup.SubType
            if #items == 2 then break end
        end
    end
    return items
end

function M:serializeState()
    local state = self.floorState
    local items = self:currentOptionItems()
    local players = {}
    self:eachPlayer(function(player, index)
        local data = player:GetData()
        if data[KEY_ACTIVE] then
            players[#players + 1] = table.concat({
                tostring(index), tostring(data[KEY_QUALITY] or 0),
                tostring(data[KEY_MULT] or 1),
            }, ",")
        end
    end)
    return table.concat({
        "FF3", state and state.key or "",
        state and tostring(state.spawned) or "false",
        state and tostring(state.resolved) or "false",
        state and tostring(state.declined) or "false",
        state and tostring(state.optionGroup) or "0",
        table.concat(items, ","), table.concat(players, ";"),
    }, "|")
end

function M:saveState()
    if self.manager.mod and self.manager.mod.SaveData and self.floorState then
        self.manager.mod:SaveData(self:serializeState())
    end
end

function M:restoreState()
    local mod = self.manager.mod
    if not mod or not mod.HasData or not mod:HasData() then
        return false
    end
    local version, key, spawned, resolved, declined, group, itemText, players =
        string.match(mod:LoadData() or "",
            "^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if (version ~= "FF3" and version ~= "FF2") or key ~= self:floorKey() then
        return false
    end
    self:newFloorState()
    local state = self.floorState
    state.spawned = spawned == "true"
    state.resolved = resolved == "true"
    state.declined = declined == "true"
    state.optionGroup = tonumber(group) or 0
    if state.spawned and not state.resolved and not state.declined then
        local first, second = string.match(itemText or "", "^(%d+),(%d+)$")
        if first and second and self:isStartingRoom() then
            state.restoredItems = { tonumber(first), tonumber(second) }
            state.spawned = false
            state.pendingSpawn = true
            state.spawnFrame = Game():GetFrameCount()
                + self:cfg("spawnDelayFrames", 1)
        else
            state.spawned = false
            state.declined = true
        end
    end
    for entry in string.gmatch(players or "", "[^;]+") do
        local index, quality, mult = string.match(entry, "^(%d+),([^,]+),([^,]+)$")
        local player = index and Isaac.GetPlayer(tonumber(index)) or nil
        if player then
            local data = player:GetData()
            data[KEY_ACTIVE] = true
            data[KEY_QUALITY] = tonumber(quality) or 0
            data[KEY_MULT] = tonumber(mult) or 1
            self:refreshDamage(player)
        end
    end
    return true
end

function M:grantTestItem(continued)
    if continued or not self:cfg("grantOnNewGame", false) then
        return false
    end
    local player = Isaac.GetPlayer(0)
    if not player or player:HasCollectible(self.itemId) then
        return false
    end
    player:AddCollectible(self.itemId, 0, true)
    Isaac.DebugString("[PenitentRelics] Forbidden Fruit granted for testing")
    return true
end

function M:onGameStart(continued)
    self.initializing = true
    self.pendingPick = nil
    self:clearDebuffVisuals()
    self:removeOptions()
    if continued and self:restoreState() then
        self.initializing = false
        return
    end
    self:clearAllPenalties()
    self:newFloorState()
    self:grantTestItem(continued)
    if self:isSupportedFloor() and self:anyLivingHolder() then
        self.floorState.pendingSpawn = true
        self.floorState.spawnFrame = Game():GetFrameCount()
            + self:cfg("spawnDelayFrames", 1)
    end
    self.initializing = false
end

function M:onRegister(manager)
    self.initializing = false
    self.pendingPick = nil
    self.debuffVisuals = {}
    self.itemId = Isaac.GetItemIdByName(ITEM_NAME)
    if not self.itemId or self.itemId < 1 then
        manager.Util.warn("Forbidden Fruit registration failed: item not found")
        return
    end
    self.visualVariant = Isaac.GetEntityVariantByName(VISUAL_NAME)
    if not self.visualVariant or self.visualVariant < 1 then
        self.visualVariant = nil
        manager.Util.warn("Forbidden Fruit debuff visual entity was not found")
    end
    manager:addCallback(ModCallbacks.MC_POST_NEW_LEVEL, function(_)
        manager.Util.safeCall(function() self:onNewLevel() end,
            "MC_POST_NEW_LEVEL(forbidden_fruit)")
    end)
    manager:addCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION,
        function(_, pickup, collider)
            local result = nil
            manager.Util.safeCall(function()
                result = self:onPrePickupCollision(pickup, collider)
            end, "MC_PRE_PICKUP_COLLISION(forbidden_fruit)")
            return result
        end, PickupVariant.PICKUP_COLLECTIBLE)
    manager:addCallback(ModCallbacks.MC_POST_PICKUP_UPDATE,
        function(_, pickup)
            manager.Util.safeCall(function() self:onPickupUpdate(pickup) end,
                "MC_POST_PICKUP_UPDATE(forbidden_fruit)")
        end, PickupVariant.PICKUP_COLLECTIBLE)
    manager:addCallback(ModCallbacks.MC_POST_ENTITY_REMOVE, function(_, entity)
        manager.Util.safeCall(function() self:onEntityRemove(entity) end,
            "MC_POST_ENTITY_REMOVE(forbidden_fruit)")
    end, EntityType.ENTITY_PICKUP)
    manager:addCallback(ModCallbacks.MC_PRE_GAME_EXIT, function(_, shouldSave)
        if shouldSave then self:saveState() end
    end)
    if EID and EID.addCollectible then
        EID:addCollectible(self.itemId,
            "At each floor start, choose one of two Treasure Room items before leaving\n"
            .. "Each choice is a one-heart devil deal; Keepers pay coins\n"
            .. "Chosen quality reduces damage by 0/10/20/30/40% for the floor\n"
            .. "Refusing has no penalty", ITEM_NAME, "en_us")
    end
    Isaac.DebugString("[PenitentRelics] Forbidden Fruit ready: giveitem c"
        .. tostring(self.itemId))
end

return M
