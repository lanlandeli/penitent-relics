-- ============================================================================
-- Penitent Relics / framework / util.lua
-- General helpers: logging, safe calls, color and vector utilities
-- ============================================================================

local Util = {}

-- Debug log switch (written from the global config by the manager at init)
Util.debugEnabled = false

-- Runtime error counter (checkable in-game via log.txt)
Util.errCount = 0

-- ---------------------------------------------------------------------------
-- Logging: when debug is enabled, output goes to the game log.txt (print is
-- recorded by the game)
-- ---------------------------------------------------------------------------
function Util.log(msg)
    if Util.debugEnabled then
        print("[PenitentRelics] " .. tostring(msg))
    end
end

function Util.warn(msg)
    print("[PenitentRelics][WARN] " .. tostring(msg))
end

-- ---------------------------------------------------------------------------
-- Safe call: pcall wrapper; an error in one module never affects the others
-- or the game.
--   fn:      the function to call
--   context: description used on error (e.g. "onTearUpdate(frost_tear)")
-- Returns the ok boolean
-- ---------------------------------------------------------------------------
function Util.safeCall(fn, context)
    local ok, err = pcall(fn)
    if not ok then
        Util.errCount = Util.errCount + 1
        Util.warn("Module callback failed [" .. context .. "]: " .. tostring(err))
    end
    return ok
end

-- ---------------------------------------------------------------------------
-- Vector helpers
-- ---------------------------------------------------------------------------

-- Angle (degrees) to velocity vector
function Util.angleToVector(angleDeg, length)
    local rad = math.rad(angleDeg)
    return Vector(math.cos(rad) * length, math.sin(rad) * length)
end

-- Random-direction vector
function Util.randomAngleVector(length)
    return Util.angleToVector(math.random() * 360, length)
end

-- ---------------------------------------------------------------------------
-- Color helpers (the game Color constructor takes RGBA components; HSV
-- conversion is provided here)
-- ---------------------------------------------------------------------------

-- HSV -> Color (h: 0~360, s/v: 0~1)
function Util.hsvColor(h, s, v)
    local c = v * s
    local hp = h / 60
    local x = c * (1 - math.abs(hp % 2 - 1))
    local r, g, b = 0, 0, 0
    if hp < 1 then
        r, g, b = c, x, 0
    elseif hp < 2 then
        r, g, b = x, c, 0
    elseif hp < 3 then
        r, g, b = 0, c, x
    elseif hp < 4 then
        r, g, b = 0, x, c
    elseif hp < 5 then
        r, g, b = x, 0, c
    else
        r, g, b = c, 0, x
    end
    local m = v - c
    return Color(r + m, g + m, b + m, 1, 0, 0, 0, 0)
end

return Util
