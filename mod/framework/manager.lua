-- ============================================================================
-- Penitent Relics / framework / manager.lua
-- Gameplay-module manager: registration, enable state, lifecycle dispatch,
--                ownership marks and damage helpers
-- ----------------------------------------------------------------------------
-- Responsibilities:
--   * Module loading/validation (pcall-isolated; a failing module never
--     breaks the rest of the framework)
--   * Precompiled per-event dispatch lists (only enabled modules that declare
--     the event are called)
--   * Per-module pcall isolation on every dispatch; errors are logged only
--   * GetData-based ownership marks for tears and other entities
--   * Incidental damage helper with a same-frame lock against
--     MC_ENTITY_TAKE_DMG recursion
-- ============================================================================

local Manager = {}

-- Framework components (mounted in init)
Manager.mod = nil        -- the mod object returned by RegisterMod
Manager.Util = nil
Manager.Config = nil
Manager.Variants = nil
Manager.Context = nil
Manager.Hooks = nil

-- Module table: moduleId -> module definition table.
Manager.modules = {}

-- Stable manifest order. Return-bearing callbacks must not depend on pairs()
-- iteration order when more than one module observes the same event.
Manager.moduleOrder = {}

-- Enable state: effectId -> boolean
Manager.enabled = {}

-- Lifecycle dispatch lists: event name -> array of modules (built by
-- rebuildDispatchLists)
Manager.hookTargets = {}

-- Incidental-damage frame lock (prevents TAKE_DMG recursion)
Manager._lockFrame = -1
Manager._locks = {}

-- ---------------------------------------------------------------------------
-- All lifecycle events (the module interface). The callback signature of each
-- event is documented at the corresponding hooks dispatch site.
-- ---------------------------------------------------------------------------
local LIFECYCLE_EVENTS = {
    -- Game lifecycle
    "onGameStart", "onNewRoom", "onUpdate", "onRender", "onPlayerUpdate",
    "onEvaluateCache", "onUseItem", "onAttackHit",
    "onNpcInit", "onNpcUpdate", "onPlayerCollide", "onNpcCollide",
    -- Tear layer
    "onFireTear", "onTearInit", "onTearUpdate", "onTearRender",
    "onTearHit", "onTearCollide",
    -- Non-tear weapon layer
    "onLaserInit", "onLaserUpdate", "onLaserRender",
    "onBombInit", "onBombUpdate", "onBombRender",
    "onKnifeInit", "onKnifeUpdate", "onKnifeRender",
}

-- ---------------------------------------------------------------------------
-- Initialize the framework (called by main.lua)
-- ---------------------------------------------------------------------------
function Manager:init(mod)
    self.mod = mod

    -- Mount components
    self.Util = include("framework.util")
    self.Config = include("framework.config")
    self.Variants = include("framework.variants")
    self.Context = include("framework.context")
    self.Hooks = include("framework.hooks")

    -- Read the global config and sync the debug log switch
    self.Config:init()
    self.Util.debugEnabled = self.Config:isDebugEnabled()

    self.Util.log("Initializing framework (version " .. tostring(mod.VERSION) .. ")")

    -- Load gameplay modules.
    self:loadModules()

    -- Register the global game callbacks (registered once, dispatched centrally)
    self.Hooks:init(self)

    -- Framework-ready log
    self.Util.log("Framework ready. Loaded modules: " .. self:moduleSummary())
end

-- ---------------------------------------------------------------------------
-- Module loading: load each module listed in modules/manifest.lua
-- ---------------------------------------------------------------------------
function Manager:loadModules()
    -- init normally runs once, but resetting the registries keeps reloads and
    -- framework tests deterministic without retaining stale module order.
    self.modules = {}
    self.enabled = {}
    self.moduleOrder = {}
    local ok, manifest = pcall(include, "modules.manifest")
    if not ok or type(manifest) ~= "table" then
        self.Util.warn("Failed to load modules/manifest.lua; no gameplay modules were loaded.")
        return
    end

    for _, id in ipairs(manifest) do
        self:loadModule(id)
    end
    self:rebuildDispatchLists()
end

-- Load a single module (pcall-isolated)
function Manager:loadModule(id)
    local ok, module = pcall(include, "modules." .. id .. ".init")
    if not ok or type(module) ~= "table" then
        local err = ok and "module did not return a table" or tostring(module)
        self.Util.warn("Failed to load gameplay module [" .. id .. "]: " .. err)
        return
    end

    -- Validation: force the id to match the manifest and register the module
    module.id = id
    module.manager = self
    self.modules[id] = module
    self.moduleOrder[#self.moduleOrder + 1] = id

    -- Register a custom tear variant when the module declares one
    if module.customVariantName then
        local variantId = self.Variants:register(id, module.customVariantName)
        if variantId then
            self.Util.log("Registered custom variant for effect [" .. id .. "]: " .. tostring(variantId))
        else
            self.Util.warn("Custom variant for effect [" .. id .. "] was not found; check content/entities2.xml: " .. module.customVariantName)
        end
    end

    -- Enable state (the global config can disable a module)
    self.enabled[id] = self.Config:isEnabled(module)

    -- Module registration hook (called whether enabled or not, so variants and
    -- extra callbacks can still be registered)
    self.Util.safeCall(function()
        if module.onRegister then
            module:onRegister(self)
        end
    end, "onRegister(" .. id .. ")")

    self.Util.log("Loaded module: " .. id .. (self.enabled[id] and "" or " (disabled by configuration)"))
end

-- ---------------------------------------------------------------------------
-- Dispatch lists: per-event arrays of "enabled modules that declare the
-- event", rebuilt once per load so per-frame dispatch is a plain array walk
-- ---------------------------------------------------------------------------
function Manager:rebuildDispatchLists()
    self.hookTargets = {}
    for _, event in ipairs(LIFECYCLE_EVENTS) do
        local list = {}
        if event == "onUseItem" then
            for _, id in ipairs(self.moduleOrder) do
                local module = self.modules[id]
                if self.enabled[id] and type(module[event]) == "function" then
                    list[#list + 1] = module
                end
            end
        else
            -- Preserve the existing dispatch construction for legacy events;
            -- expanding the item framework must not reorder current behavior.
            for id, module in pairs(self.modules) do
                if self.enabled[id] and type(module[event]) == "function" then
                    list[#list + 1] = module
                end
            end
        end
        self.hookTargets[event] = list
    end
end

-- Return-bearing dispatch for callbacks such as MC_USE_ITEM. Modules are
-- called in manifest order and remain pcall-isolated. A module that merely
-- observes the event returns nil; when several modules return a value, the
-- last non-nil value wins, matching the engine's callback convention.
function Manager:dispatchWithResult(event, ...)
    local list = self.hookTargets[event]
    if not list then
        return nil
    end
    local n = select("#", ...)
    local args = { ... }
    local result = nil
    for i = 1, #list do
        local module = list[i]
        self.Util.safeCall(function()
            local moduleResult = module[event](module, table.unpack(args, 1, n))
            if moduleResult ~= nil then
                result = moduleResult
            end
        end, event .. "(" .. module.id .. ")")
    end
    return result
end

-- ---------------------------------------------------------------------------
-- Event dispatch: walk the dispatch list, pcall-isolating each module
-- ---------------------------------------------------------------------------
function Manager:dispatch(event, ...)
    local list = self.hookTargets[event]
    if not list then
        return
    end
    -- Note: Lua 5.2+ does not allow ... inside nested closures, so the varargs
    -- are packed first (preserving nil positions) and unpacked with
    -- table.unpack inside the closure.
    local n = select("#", ...)
    local args = { ... }
    for i = 1, #list do
        local module = list[i]
        self.Util.safeCall(function()
            module[event](module, table.unpack(args, 1, n))
        end, event .. "(" .. module.id .. ")")
    end
end

-- Overridable event dispatch: must return nil when no module returned a value.
-- For the PRE_*_COLLISION callbacks, true/false both change the native
-- collision handling; therefore true must never be used as the default
-- "allow collision" value.
function Manager:dispatchWithCancel(event, ...)
    return self:dispatchWithResult(event, ...)
end

-- ---------------------------------------------------------------------------
-- Ownership marks: tie a gameplay module to an entity through
-- Entity:GetData(). This does not consume any game TearFlags, so the number
-- of gameplay modules is not limited by the few spare high bits.
-- ---------------------------------------------------------------------------
function Manager:setMark(moduleId, tear)
    local data = tear:GetData()
    data["penitentrelics_" .. moduleId] = true
end

function Manager:hasMark(moduleId, tear)
    local data = tear:GetData()
    return data["penitentrelics_" .. moduleId] == true
end

-- ---------------------------------------------------------------------------
-- Incidental damage helper: deal extra damage to a target with a same-frame,
-- same-entity lock against MC_ENTITY_TAKE_DMG recursion.
-- channel is an optional string (e.g. moduleId .. ":" .. GetPtrHash(attack)).
-- The lock is per (frame, target, channel): different modules or attack
-- entities can each settle damage on the same target in the same frame, while
-- repeated callbacks from the same attack on the same target stay blocked.
-- When channel is omitted the old per-(frame, target) behavior is preserved.
-- Returns true when the damage was dealt; false when it was skipped because
-- the same target already received damage this frame on this channel.
-- ---------------------------------------------------------------------------
function Manager:dealDamage(target, amount, dmgFlags, source, channel)
    if not target or not target:Exists() then
        return false
    end
    local frame = Game():GetFrameCount()
    if self._lockFrame ~= frame then
        self._lockFrame = frame
        self._locks = {}
    end
    -- IsaacDocs: separate Lua userdata values can refer to the same engine
    -- entity. GetPtrHash provides the stable identity required across callbacks.
    local lockKey = GetPtrHash(target)
    if channel ~= nil then
        lockKey = lockKey .. ":" .. tostring(channel)
    end
    if self._locks[lockKey] then
        return false
    end
    self._locks[lockKey] = true
    target:TakeDamage(amount, dmgFlags or 0, source or EntityRef(target), 1)
    return true
end

-- ---------------------------------------------------------------------------
-- Convenience helpers for modules
-- ---------------------------------------------------------------------------

-- Read the merged module config (global > module defaults)
function Manager:getConfig(module, key, default)
    return self.Config:get(module, key, default)
end

-- Enable/disable a module at runtime (rebuilds the dispatch lists)
function Manager:setEnabled(id, enabled)
    if not self.modules[id] then
        return
    end
    self.enabled[id] = enabled
    self:rebuildDispatchLists()
end

function Manager:isEnabled(id)
    return self.enabled[id] == true
end

function Manager:findPlayerWithCollectible(itemId)
    return self.Context.findPlayerWithCollectible(itemId)
end

function Manager:anyPlayerHasCollectible(itemId)
    return self:findPlayerWithCollectible(itemId) ~= nil
end

-- Register an extra game callback outside the lifecycle events.
-- Note: when entityType is nil, do not pass a third argument to AddCallback --
-- nil filter parameters are handled unreliably by this game version (normal
-- mods pass only 2 arguments).
function Manager:addCallback(callbackId, fn, entityType)
    if entityType ~= nil then
        self.mod:AddCallback(callbackId, fn, entityType)
    else
        self.mod:AddCallback(callbackId, fn)
    end
end

-- Register an extra callback with explicit native priority. This keeps
-- ordering-sensitive engine callbacks behind the same framework boundary as
-- ordinary extra callbacks.
function Manager:addPriorityCallback(callbackId, priority, fn, entityType)
    if entityType ~= nil then
        self.mod:AddPriorityCallback(callbackId, priority, fn, entityType)
    else
        self.mod:AddPriorityCallback(callbackId, priority, fn)
    end
end

-- Loaded-module summary (for logs)
function Manager:moduleSummary()
    local names = {}
    for id in pairs(self.modules) do
        names[#names + 1] = id
    end
    table.sort(names)
    return table.concat(names, ", ")
end

return Manager
