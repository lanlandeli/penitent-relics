-- ============================================================================
-- Penitent Relics global configuration
-- ----------------------------------------------------------------------------
-- debug: when true, the framework writes module loading and call logs to the
--        game log.txt (Documents/My Games/Binding of Isaac Repentance+/log.txt)
-- modules: per-module overrides, keyed by module id. Supported keys:
--   enabled    whether the effect is enabled (false excludes it from dispatch)
--   other keys override module default parameters (the module's config table
--              defines which keys can be overridden)
-- ============================================================================
return {
    debug = true,

    modules = {
        -- Item effect: Crude Salt (active while held)
        crude_salt = {
            enabled = true,
            baseChance = 0.40,     -- salt-tear trigger chance at 0 Luck
            maxLuck = 8.0,         -- Luck at which the trigger chance reaches 100%
            tearScale = 1.15,      -- visual scale of salt tears
            tearPulseInterval = 3, -- frames between granular tear-color steps
            reverseCos = -0.5,     -- reversal threshold (angle > 120 degrees)
            graceFrames = 5,       -- grace period after a hit (ignores knockback)
            requireFrames = 3,     -- consecutive reversal frames to shatter
            minMoveSpeed = 0.25,   -- below this speed the enemy counts as stationary
            markHeightPadding = 6, -- extra vertical spacing above the target
            markSizeRatio = 0.90,  -- icon size relative to target collision size
            markMinScale = 0.34,   -- minimum overhead-icon scale
            markMaxScale = 0.78,   -- maximum overhead-icon scale
            markBackstabOffset = 12, -- horizontal offset when Backstabber is active
            statueFrames = 60,     -- how long the enemy is displayed as a salt statue (~2s)
            bossDamageMult = 5.0,  -- boss shatter damage (x the owner's damage)
            normalFatalDamage = 1000000, -- minimum armor-ignoring normal-enemy damage
            shatterEffectFrames = 16, -- authored salt-shatter visual duration
            shatterSizeRatio = 2.2, -- shatter size relative to target collision size
            shatterMinScale = 0.40,
            shatterMaxScale = 2.25,
        },

        -- Item effect: Trinity (active while held)
        trinity = {
            enabled = true,
            -- tearsBonus = 0.7,        -- flat tears-up added after item is acquired
            -- judgmentDamageMult = 5.0 -- example override
            -- judgmentSoundEnabled = true,
            -- judgmentSoundVolume = 0.90,
            -- judgmentSoundPitch = 1.00,
            -- laserTierTicks = 8,     -- persistent laser updates per aspect
            -- knifeTierTicks = 8,     -- active Mom's Knife updates per aspect
            -- laserMuzzleFrames = 38, -- normal Brimstone duration; sustained beams repeat
            -- laserMuzzleScale = 1.10,
        },

        -- Item effect: Forbidden Fruit (floor-local choice and penalty)
        forbidden_fruit = {
            enabled = true,
            q0DamageMult = 1.00,
            q1DamageMult = 0.90,
            q2DamageMult = 0.80,
            q3DamageMult = 0.70,
            q4DamageMult = 0.60,
            optionSpacing = 72,
            spawnDelayFrames = 1,
            debuffVisualEnabled = true,
            debuffVisualHeight = 38,
            grantOnNewGame = true, -- testing only: give player 1 the item on a new run
        },
    },
}
