-- ============================================================================
-- Penitent Relics / framework / context.lua
-- Attack context helpers: build a unified context table (ctx) for tears,
-- lasers, knives and bombs, and resolve the owning player.
-- ----------------------------------------------------------------------------
-- Player ownership is resolved through Parent first and SpawnerEntity second.
-- This matches how tears from the player, Incubus and other weapon entities are
-- linked by the game. EntityRef.SpawnerType remains a useful fallback when the
-- original player pointer is no longer available in MC_ENTITY_TAKE_DMG.

local Context = {}
local pendingKnifeHits = {}

local ET = EntityType

local ATTACK_TYPES = {
    [ET.ENTITY_TEAR] = "tear",
    [ET.ENTITY_LASER] = "laser",
    [ET.ENTITY_KNIFE] = "knife",
    [ET.ENTITY_BOMBDROP] = "bomb",
}

local function asPlayer(entity)
    if not entity then
        return nil
    end
    local player = entity:ToPlayer()
    if player then
        return player
    end
    local familiar = entity:ToFamiliar()
    if familiar and familiar.Player then
        return familiar.Player
    end
    return nil
end

function Context.resolvePlayer(entity)
    local current = entity
    local seen = {}

    for _ = 1, 6 do
        if not current then
            break
        end

        local seed = current.InitSeed
        if seed and seen[seed] then
            break
        end
        if seed then
            seen[seed] = true
        end

        local player = asPlayer(current)
        if player then
            return player
        end

        -- Parent is the more reliable owner for several familiar-fired tears.
        local parent = current.Parent
        player = asPlayer(parent)
        if player then
            return player
        end

        local spawner = current.SpawnerEntity
        player = asPlayer(spawner)
        if player then
            return player
        end

        current = parent or spawner
    end

    -- In a single-player run SpawnerType is sufficient to identify the owner.
    -- This fallback is important because EntityRef can retain SpawnerType while
    -- its Entity/SpawnerEntity pointers are unavailable in the damage callback.
    if entity and entity.SpawnerType == ET.ENTITY_PLAYER
        and Game():GetNumPlayers() == 1 then
        return Isaac.GetPlayer(0)
    end

    return nil
end

function Context.findPlayerWithCollectible(itemId)
    for i = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player and player:HasCollectible(itemId) then
            return player
        end
    end
    return nil
end

function Context.buildBase(entity, ctxType, weaponType)
    local player = Context.resolvePlayer(entity)
    return {
        type = ctxType,
        player = player,
        isPlayerOwned = player ~= nil,
        weaponType = weaponType,
        variant = entity.Variant,
        isSpecial = entity.Variant ~= 0,
        entity = entity,
    }
end

function Context.buildTearContext(tear)
    local ctx = Context.buildBase(tear, "tear", WeaponType.WEAPON_TEARS)
    ctx.tear = tear
    return ctx
end

function Context.buildLaserContext(laser)
    local ctx = Context.buildBase(laser, "laser", WeaponType.WEAPON_LASER)
    ctx.laser = laser
    return ctx
end

function Context.buildKnifeContext(knife)
    local ctx = Context.buildBase(knife, "knife", WeaponType.WEAPON_KNIFE)
    ctx.knife = knife
    return ctx
end

function Context.buildBombContext(bomb)
    local ctx = Context.buildBase(bomb, "bomb", WeaponType.WEAPON_BOMBS)
    ctx.bomb = bomb
    return ctx
end

function Context.buildDamageContext(source, damageFlags)
    if not source then
        return nil
    end

    local ctxType = ATTACK_TYPES[source.Type]
    local isLaserDamage = damageFlags
        and (damageFlags & DamageFlag.DAMAGE_LASER) ~= 0
    if isLaserDamage then
        ctxType = "laser"
    end
    if not ctxType then
        return nil
    end

    local attack = source.Entity
    if (ctxType == "laser" and attack and attack.Type ~= ET.ENTITY_LASER)
        or (ctxType == "knife" and attack and attack.Type ~= ET.ENTITY_KNIFE) then
        -- Native lasers and knife hitboxes can report their player as
        -- EntityRef.Entity. Preserve ownership, then recover the live weapon.
        attack = nil
    end
    local sourceEntity = source.Entity
    local player = sourceEntity and Context.resolvePlayer(sourceEntity) or nil
    local playerOwned = player ~= nil
        or source.SpawnerType == ET.ENTITY_PLAYER
        or (sourceEntity and sourceEntity.SpawnerType == ET.ENTITY_PLAYER)

    return {
        type = ctxType,
        source = source,
        entity = attack,
        player = player,
        isPlayerOwned = playerOwned,
        sourceType = source.Type,
        variant = source.Variant,
    }
end

function Context.rememberKnifeCollision(knife, target)
    if not knife or not target then
        return
    end
    local ctx = Context.buildKnifeContext(knife)
    if not ctx.isPlayerOwned then
        return
    end
    pendingKnifeHits[GetPtrHash(target)] = {
        frame = Game():GetFrameCount(),
        knife = EntityPtr(knife),
    }
end

function Context.recoverKnifeDamageContext(target, source, ctx)
    if not target then
        return ctx
    end
    local targetHash = GetPtrHash(target)
    local pending = pendingKnifeHits[targetHash]
    if not pending or pending.frame ~= Game():GetFrameCount() then
        pendingKnifeHits[targetHash] = nil
        return ctx
    end

    local sourceEntity = source and source.Entity or nil
    local playerReported = source and (source.Type == ET.ENTITY_PLAYER
        or source.SpawnerType == ET.ENTITY_PLAYER
        or (sourceEntity and sourceEntity.Type == ET.ENTITY_PLAYER))
    local needsRecovery = (ctx and ctx.type == "knife" and not ctx.entity)
        or (not ctx and playerReported)
    if not needsRecovery then
        return ctx
    end

    -- Consume before Trinity submits supplemental player-sourced damage, so
    -- that damage cannot recursively recover the same knife collision.
    pendingKnifeHits[targetHash] = nil
    local knife = pending.knife.Ref
    if not knife or not knife:Exists() or knife.Type ~= ET.ENTITY_KNIFE then
        return ctx
    end
    local recovered = Context.buildKnifeContext(knife)
    if not recovered.isPlayerOwned then
        return ctx
    end
    recovered.source = source
    recovered.sourceType = source and source.Type or ET.ENTITY_KNIFE
    return recovered
end

function Context.clearKnifeCollisions()
    pendingKnifeHits = {}
end

return Context
