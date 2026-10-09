-- Regression tests for the Repentance+ runtime gate in mod/main.lua.

local function loadMain(overrides)
    local registered = {}
    local env = {
        REPENTANCE_PLUS = overrides.REPENTANCE_PLUS,
        RegisterMod = function(name, apiVersion)
            local mod = { name = name, apiVersion = apiVersion }
            registered[#registered + 1] = mod
            return mod
        end,
        include = overrides.include or function()
            return { init = function() end }
        end,
        print = function() end,
        pcall = pcall,
        tostring = tostring,
        type = type,
    }
    return assert(loadfile("mod/main.lua", "t", env))(), registered
end

local mod = loadMain({ REPENTANCE_PLUS = false })
assert(mod.LOAD_FAILED == "Repentance+ is required.",
    "Repentance+ dependency gate did not fail closed")

local initialized = nil
mod = loadMain({
    REPENTANCE_PLUS = true,
    include = function(path)
        assert(path == "framework.manager", "main included an unexpected component")
        return {
            init = function(_, runtimeMod)
                initialized = runtimeMod
            end,
        }
    end,
})
assert(initialized == mod and mod.ModuleManager,
    "supported runtime did not initialize the framework")
assert(mod.IS_REPENTANCE_PLUS,
    "vanilla Repentance+ runtime metadata was not exposed")

print("Main dependency-gate regression tests passed.")
