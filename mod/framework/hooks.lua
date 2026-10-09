-- ============================================================================
-- Penitent Relics / framework / hooks.lua
-- Central game-callback registration and dispatch
-- ----------------------------------------------------------------------------
-- Every game callback is registered exactly once; the handler filters for
-- "attacks initiated by the player" and then dispatches to the manager.
-- Dispatch goes through manager:dispatch (per-module pcall isolation).
--
-- IMPORTANT (standard AB+/Repentance behavior):
--   The game passes the mod object as the first argument to every registered
--   callback, so the callback signature is always (mod, ...). All closures
--   below therefore name the first parameter _, and business parameters
--   start at position 2.
--
-- Note: game callbacks are invoked without `self`, so every AddCallback uses
-- a closure to let the handler be called as a method (self = this table).
-- ----------------------------------------------------------------------------
-- Module interface signatures (all optional; the mod parameter is omitted):
--   onGameStart(continued)                     MC_POST_GAME_STARTED
--   onNewRoom()                                MC_POST_NEW_ROOM
--   onUpdate()                                 MC_POST_UPDATE
--   onRender()                                 MC_POST_RENDER
--   onPlayerUpdate(player)                     MC_POST_PEFFECT_UPDATE
--   onEvaluateCache(player, cacheFlag)         MC_EVALUATE_CACHE
--   onUseItem(itemId, rng, player, useFlags, activeSlot, customVarData)
--                                              MC_USE_ITEM
--   onFireTear(tear, ctx)                      MC_POST_FIRE_TEAR
--   onTearInit(tear, ctx)                      MC_POST_TEAR_INIT
--   onTearUpdate(tear, ctx)                    MC_POST_TEAR_UPDATE
--   onTearRender(tear, offset, ctx)            MC_POST_TEAR_RENDER
--   onAttackHit(target, amount, dmgFlags, source, countdownFrames, ctx)
--                                              MC_ENTITY_TAKE_DMG (all player weapons)
--   onTearHit(tear, target, amount, dmgFlags, source, ctx)
--                                              tear-specific sub-event of onAttackHit
--   onTearCollide(tear, target, low, ctx)      MC_PRE_TEAR_COLLISION (nil keeps vanilla behavior)
--   onPlayerCollide(player, collider, low)     MC_PRE_PLAYER_COLLISION (nil keeps vanilla behavior)
--   onNpcCollide(npc, collider, low)           MC_PRE_NPC_COLLISION (nil keeps vanilla behavior)
--   onNpcInit(npc)                             MC_POST_NPC_INIT
--   onNpcUpdate(npc)                           MC_PRE_NPC_UPDATE (true skips native AI/update)
--   onLaserInit/Update/Render(laser, [offset], ctx)   MC_POST_LASER_*
--   onBombInit/Update/Render(bomb, [offset], ctx)     MC_POST_BOMB_*
--   onKnifeInit/Update/Render(knife, [offset], ctx)   MC_POST_KNIFE_*
-- ============================================================================

local Hooks = {}

local MC = ModCallbacks
function Hooks:init(manager)
    self.manager = manager
    local mod = manager.mod

    -- ---- Game lifecycle ----
    mod:AddCallback(MC.MC_POST_GAME_STARTED, function(_, continued) self:onGameStarted(continued) end)
    mod:AddCallback(MC.MC_POST_NEW_ROOM, function(_) self:onNewRoom() end)
    mod:AddCallback(MC.MC_POST_UPDATE, function(_) self:onUpdate() end)
    mod:AddCallback(MC.MC_POST_RENDER, function(_) self:onRender() end)
    mod:AddCallback(MC.MC_POST_PEFFECT_UPDATE, function(_, player)
        self:onPlayerUpdate(player)
    end)
    -- Stats recalculations: fires per cache flag whenever the game re-evaluates
    -- a player's stats (pickup/removal/stat changes). Modules check cacheFlag
    -- themselves and only modify the stat for their own flag.
    mod:AddCallback(MC.MC_EVALUATE_CACHE, function(_, player, cacheFlag) self:onEvaluateCache(player, cacheFlag) end)
    mod:AddCallback(MC.MC_USE_ITEM, function(_, itemId, rng, player, useFlags, activeSlot, customVarData)
        return self:onUseItem(itemId, rng, player, useFlags, activeSlot, customVarData)
    end)

    -- ---- Tear lifecycle ----
    mod:AddCallback(MC.MC_POST_FIRE_TEAR, function(_, tear) self:onFireTear(tear) end)
    mod:AddCallback(MC.MC_POST_TEAR_INIT, function(_, tear) self:onTearInit(tear) end)
    mod:AddCallback(MC.MC_POST_TEAR_UPDATE, function(_, tear) self:onTearUpdate(tear) end)
    mod:AddCallback(MC.MC_POST_TEAR_RENDER, function(_, tear, offset) self:onTearRender(tear, offset) end)
    mod:AddCallback(MC.MC_PRE_TEAR_COLLISION, function(_, tear, entity, low)
        return self:onPreTearCollision(tear, entity, low)
    end)
    mod:AddCallback(MC.MC_PRE_PLAYER_COLLISION, function(_, player, collider, low)
        return self:onPrePlayerCollision(player, collider, low)
    end)
    mod:AddCallback(MC.MC_PRE_NPC_COLLISION, function(_, npc, collider, low)
        return self:onPreNpcCollision(npc, collider, low)
    end)
    mod:AddCallback(MC.MC_POST_NPC_INIT, function(_, npc)
        self.manager:dispatch("onNpcInit", npc)
    end)
    mod:AddCallback(MC.MC_PRE_NPC_UPDATE, function(_, npc)
        return self.manager:dispatchWithCancel("onNpcUpdate", npc)
    end)

    -- ---- Damage detection (registered globally; player tears are filtered
    --      inside the handler) ----
    mod:AddCallback(MC.MC_ENTITY_TAKE_DMG, function(_, entity, amount, dmgFlags, source, countdownFrames)
        self:onEntityTakeDmg(entity, amount, dmgFlags, source, countdownFrames)
    end)

    -- ---- Non-tear weapons (laser / bomb / knife) ----
    mod:AddCallback(MC.MC_POST_LASER_INIT, function(_, laser) self:onLaserInit(laser) end)
    mod:AddCallback(MC.MC_POST_LASER_UPDATE, function(_, laser) self:onLaserUpdate(laser) end)
    mod:AddCallback(MC.MC_POST_LASER_RENDER, function(_, laser, offset) self:onLaserRender(laser, offset) end)
    mod:AddCallback(MC.MC_POST_BOMB_INIT, function(_, bomb) self:onBombInit(bomb) end)
    mod:AddCallback(MC.MC_POST_BOMB_UPDATE, function(_, bomb) self:onBombUpdate(bomb) end)
    mod:AddCallback(MC.MC_POST_BOMB_RENDER, function(_, bomb, offset) self:onBombRender(bomb, offset) end)
    mod:AddCallback(MC.MC_POST_KNIFE_INIT, function(_, knife) self:onKnifeInit(knife) end)
    mod:AddCallback(MC.MC_POST_KNIFE_UPDATE, function(_, knife) self:onKnifeUpdate(knife) end)
    mod:AddCallback(MC.MC_POST_KNIFE_RENDER, function(_, knife, offset) self:onKnifeRender(knife, offset) end)
    mod:AddCallback(MC.MC_PRE_KNIFE_COLLISION, function(_, knife, collider, low)
        self:onKnifeCollision(knife, collider, low)
    end)
end

-- ---------------------------------------------------------------------------
-- Game lifecycle
-- ---------------------------------------------------------------------------
function Hooks:onGameStarted(continued)
    self.manager.Context.clearKnifeCollisions()
    self.manager:dispatch("onGameStart", continued)
end

function Hooks:onNewRoom()
    self.manager.Context.clearKnifeCollisions()
    self.manager:dispatch("onNewRoom")
end

function Hooks:onUpdate()
    self.manager:dispatch("onUpdate")
end

function Hooks:onRender()
    self.manager:dispatch("onRender")
end

function Hooks:onPlayerUpdate(player)
    self.manager:dispatch("onPlayerUpdate", player)
end

-- MC_EVALUATE_CACHE: dispatched for every cache flag on every player; modules
-- must filter by cacheFlag and check item ownership before touching stats.
function Hooks:onEvaluateCache(player, cacheFlag)
    self.manager:dispatch("onEvaluateCache", player, cacheFlag)
end

-- MC_USE_ITEM may return a boolean or a table containing Discharge, Remove
-- and ShowAnim. Modules that only observe another item's activation return
-- nil; the owning active-item module may return the engine response.
function Hooks:onUseItem(itemId, rng, player, useFlags, activeSlot, customVarData)
    return self.manager:dispatchWithResult(
        "onUseItem", itemId, rng, player, useFlags, activeSlot, customVarData
    )
end

-- ---------------------------------------------------------------------------
-- Tear layer: only tears initiated by the player are processed
-- ---------------------------------------------------------------------------
function Hooks:onFireTear(tear)
    local ctx = self.manager.Context.buildTearContext(tear)
    if not ctx.isPlayerOwned then
        return
    end
    self.manager:dispatch("onFireTear", tear, ctx)
end

function Hooks:onTearInit(tear)
    local ctx = self.manager.Context.buildTearContext(tear)
    if not ctx.isPlayerOwned then
        return
    end
    self.manager:dispatch("onTearInit", tear, ctx)
end

function Hooks:onTearUpdate(tear)
    local ctx = self.manager.Context.buildTearContext(tear)
    if not ctx.isPlayerOwned then
        return
    end
    self.manager:dispatch("onTearUpdate", tear, ctx)
end

function Hooks:onTearRender(tear, offset)
    local ctx = self.manager.Context.buildTearContext(tear)
    if not ctx.isPlayerOwned then
        return
    end
    self.manager:dispatch("onTearRender", tear, offset, ctx)
end

-- Must return nil by default so the native collision and damage logic runs.
-- Modules return a boolean only when they explicitly want to override it.
function Hooks:onPreTearCollision(tear, entity, low)
    local ctx = self.manager.Context.buildTearContext(tear)
    if not ctx.isPlayerOwned then
        return
    end
    return self.manager:dispatchWithCancel("onTearCollide", tear, entity, low, ctx)
end

function Hooks:onPrePlayerCollision(player, collider, low)
    return self.manager:dispatchWithCancel("onPlayerCollide", player, collider, low)
end

function Hooks:onPreNpcCollision(npc, collider, low)
    return self.manager:dispatchWithCancel("onNpcCollide", npc, collider, low)
end

-- ---------------------------------------------------------------------------
-- Damage detection: unified onAttackHit for all effect items.
-- EntityRef.Entity can be nil in some damage events, so player ownership also
-- consults Parent, SpawnerEntity and EntityRef.SpawnerType.
-- ---------------------------------------------------------------------------
function Hooks:onEntityTakeDmg(entity, amount, dmgFlags, source, countdownFrames)
    local ctx = self.manager.Context.buildDamageContext(source, dmgFlags)
    ctx = self.manager.Context.recoverKnifeDamageContext(entity, source, ctx)
    if not ctx or not ctx.isPlayerOwned then
        return
    end

    self.manager:dispatch("onAttackHit", entity, amount, dmgFlags, source, countdownFrames, ctx)

    -- Tear-specific sub-event for future visual modules.
    if ctx.type == "tear" and ctx.entity then
        self.manager:dispatch("onTearHit", ctx.entity, entity, amount, dmgFlags, source, ctx)
    end
end

function Hooks:onKnifeCollision(knife, collider, low)
    self.manager.Context.rememberKnifeCollision(knife, collider)
end

-- ---------------------------------------------------------------------------
-- Non-tear weapon layer: player-initiated only, same as the tear layer
-- ---------------------------------------------------------------------------
function Hooks:onLaserInit(laser)
    local ctx = self.manager.Context.buildLaserContext(laser)
    if not ctx.isPlayerOwned then
        return
    end
    self.manager:dispatch("onLaserInit", laser, ctx)
end

function Hooks:onLaserUpdate(laser)
    local ctx = self.manager.Context.buildLaserContext(laser)
    if not ctx.isPlayerOwned then
        return
    end
    self.manager:dispatch("onLaserUpdate", laser, ctx)
end

function Hooks:onLaserRender(laser, offset)
    local ctx = self.manager.Context.buildLaserContext(laser)
    if not ctx.isPlayerOwned then
        return
    end
    self.manager:dispatch("onLaserRender", laser, offset, ctx)
end

function Hooks:onBombInit(bomb)
    local ctx = self.manager.Context.buildBombContext(bomb)
    if not ctx.isPlayerOwned then
        return
    end
    self.manager:dispatch("onBombInit", bomb, ctx)
end

function Hooks:onBombUpdate(bomb)
    local ctx = self.manager.Context.buildBombContext(bomb)
    if not ctx.isPlayerOwned then
        return
    end
    self.manager:dispatch("onBombUpdate", bomb, ctx)
end

function Hooks:onBombRender(bomb, offset)
    local ctx = self.manager.Context.buildBombContext(bomb)
    if not ctx.isPlayerOwned then
        return
    end
    self.manager:dispatch("onBombRender", bomb, offset, ctx)
end

function Hooks:onKnifeInit(knife)
    local ctx = self.manager.Context.buildKnifeContext(knife)
    if not ctx.isPlayerOwned then
        return
    end
    self.manager:dispatch("onKnifeInit", knife, ctx)
end

function Hooks:onKnifeUpdate(knife)
    local ctx = self.manager.Context.buildKnifeContext(knife)
    if not ctx.isPlayerOwned then
        return
    end
    self.manager:dispatch("onKnifeUpdate", knife, ctx)
end

function Hooks:onKnifeRender(knife, offset)
    local ctx = self.manager.Context.buildKnifeContext(knife)
    if not ctx.isPlayerOwned then
        return
    end
    self.manager:dispatch("onKnifeRender", knife, offset, ctx)
end

return Hooks
