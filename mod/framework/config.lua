-- ============================================================================
-- Penitent Relics / framework / config.lua
-- Configuration system: global config (mod/config.lua) > module defaults
-- (module.config)
-- ----------------------------------------------------------------------------
-- Expected structure of mod/config.lua:
--   return {
--       debug = false,                       -- global: framework debug log
--       modules = {
--           ["rainbow_tear"] = { enabled = true, hueSpeed = 3.0 },  -- per-module overrides
--       },
--   }
-- ============================================================================

local Config = {}

-- Raw global config table (from the mod-root config.lua)
Config.global = {}

-- Merged config cache: effectId -> merged parameter dictionary
Config.moduleCache = {}

-- ---------------------------------------------------------------------------
-- Initialize: read the global config (falls back to an empty table when the
-- file is missing or broken; never blocks the framework)
-- ---------------------------------------------------------------------------
function Config:init()
    local ok, cfg = pcall(include, "config")
    if ok and type(cfg) == "table" then
        self.global = cfg
    else
        self.global = {}
    end
end

-- Debug switch
function Config:isDebugEnabled()
    return self.global.debug == true
end

-- Whether a module is enabled (global config wins; module defaults otherwise)
function Config:isEnabled(module)
    local g = self.global.modules and self.global.modules[module.id]
    if g and g.enabled ~= nil then
        return g.enabled
    end
    return true -- enabled by default
end

-- ---------------------------------------------------------------------------
-- Read a merged module config: module.config defaults overridden by the
-- global config. Merged once and cached on first access; config is static
-- for a session, so there is no need to rebuild it frequently.
-- ---------------------------------------------------------------------------
function Config:get(module, key, default)
    local merged = self.moduleCache[module.id]
    if not merged then
        merged = {}
        local defaults = module.config
        if type(defaults) == "table" then
            for k, v in pairs(defaults) do
                merged[k] = v
            end
        end
        local g = self.global.modules and self.global.modules[module.id]
        if type(g) == "table" then
            for k, v in pairs(g) do
                if k ~= "enabled" then
                    merged[k] = v
                end
            end
        end
        self.moduleCache[module.id] = merged
    end

    local v = merged[key]
    if v == nil then
        return default
    end
    return v
end

-- Reload the global config (for debugging; not needed in normal flow)
function Config:reload()
    self.moduleCache = {}
    self:init()
end

return Config
