-- ============================================================================
-- Penitent Relics / main.lua
-- Mod entry: version check -> create mod object -> initialize the gameplay
-- framework
-- ----------------------------------------------------------------------------
-- Architecture:
--   This mod is a modular item expansion. The modules/ path contains gameplay
--   modules for passive/active items, attacks, stats,
--   room logic and visuals; one manifest entry enables a module.
--   The framework handles the engineering concerns: pcall-isolated module
--   loading, central game-callback registration and dispatch, GetData-based
--   ownership marks, config merging, and an anti-recursion incidental-damage
--   helper. See docs/development/module_guide.md to add a new item.
-- ============================================================================

local MOD_NAME = "Penitent Relics"
local MOD_VERSION = "0.35.0"

if not REPENTANCE_PLUS then
    local mod = RegisterMod(MOD_NAME, 1)
    mod.VERSION = MOD_VERSION
    mod.LOAD_FAILED = "Repentance+ is required."
    return mod
end

local mod = RegisterMod(MOD_NAME, 1)
mod.VERSION = MOD_VERSION
mod.IS_REPENTANCE_PLUS = true

-- Initialize the framework (all internal module loading is pcall-isolated;
-- even a framework-init failure is only logged and never affects the game)
local ok, err = pcall(function()
    local manager = include("framework.manager")
    manager:init(mod)
    mod.ModuleManager = manager
end)

if not ok then
    print("[PenitentRelics][FATAL] Framework initialization failed: " .. tostring(err))
    mod.LOAD_FAILED = "Framework initialization failed."
end

return mod
