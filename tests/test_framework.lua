-- Regression tests for framework-wide module dispatch.
-- Run from the repository root with: tools\lua\lua53.exe tests\test_framework.lua

local Manager = dofile("mod/framework/manager.lua")

Manager.Util = {
    safeCall = function(fn, label)
        local ok, result = pcall(fn)
        assert(ok, label .. ": " .. tostring(result))
        return result
    end,
}
Manager.modules = {}
Manager.enabled = {}
Manager.moduleOrder = { "observer", "owner" }

local calls = {}
Manager.modules.observer = {
    id = "observer",
    onUseItem = function(_, itemId)
        calls[#calls + 1] = "observer:" .. tostring(itemId)
        return nil
    end,
}
Manager.modules.owner = {
    id = "owner",
    onUseItem = function(_, itemId, _, player, useFlags, activeSlot, customVarData)
        calls[#calls + 1] = "owner:" .. tostring(itemId)
        assert(player.name == "Isaac", "active-item player was not forwarded")
        assert(useFlags == 4 and activeSlot == 1 and customVarData == 7,
            "active-item arguments were not forwarded")
        return { Discharge = true, Remove = false, ShowAnim = true }
    end,
}
Manager.enabled.observer = true
Manager.enabled.owner = true
Manager:rebuildDispatchLists()

local response = Manager:dispatchWithResult(
    "onUseItem", 1002, {}, { name = "Isaac" }, 4, 1, 7
)
assert(calls[1] == "observer:1002" and calls[2] == "owner:1002",
    "return-bearing lifecycle did not follow manifest order")
assert(response.Discharge and response.Remove == false and response.ShowAnim,
    "active-item response table was not preserved")

Manager.hookTargets.onUseItem = {
    {
        id = "false_response",
        onUseItem = function() return false end,
    },
}
assert(Manager:dispatchWithResult("onUseItem", 1002) == false,
    "false is a meaningful active-item response and must not become nil")

local Hooks = dofile("mod/framework/hooks.lua")
local forwarded = nil
Hooks.manager = {
    dispatchWithResult = function(_, event, ...)
        forwarded = { event = event, args = { ... } }
        return { Discharge = false, ShowAnim = true }
    end,
}
local hookResponse = Hooks:onUseItem(1003, "rng", "player", 8, 2, 11)
assert(forwarded.event == "onUseItem" and forwarded.args[1] == 1003,
    "hooks did not forward the active-item lifecycle")
assert(forwarded.args[2] == "rng" and forwarded.args[3] == "player"
    and forwarded.args[4] == 8 and forwarded.args[5] == 2 and forwarded.args[6] == 11,
    "hooks changed active-item argument order")
assert(hookResponse.Discharge == false and hookResponse.ShowAnim,
    "hooks did not preserve the active-item response")

local callbackCalls = {}
Manager.mod = {
    AddPriorityCallback = function(_, callbackId, priority, fn, filter)
        callbackCalls[#callbackCalls + 1] = {
            callbackId = callbackId,
            priority = priority,
            fn = fn,
            filter = filter,
        }
    end,
}
local priorityFn = function() end
Manager:addPriorityCallback(11, 100, priorityFn, 1)
Manager:addPriorityCallback(18, -100, priorityFn)
assert(#callbackCalls == 2, "priority callbacks were not registered")
assert(callbackCalls[1].callbackId == 11
        and callbackCalls[1].priority == 100
        and callbackCalls[1].fn == priorityFn
        and callbackCalls[1].filter == 1,
    "filtered priority callback arguments were changed")
assert(callbackCalls[2].callbackId == 18
        and callbackCalls[2].priority == -100
        and callbackCalls[2].filter == nil,
    "unfiltered priority callback should omit the filter")

print("Framework lifecycle regression tests passed.")
