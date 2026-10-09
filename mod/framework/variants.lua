-- ============================================================================
-- Penitent Relics / framework / variants.lua
-- Custom tear-variant registry
-- ----------------------------------------------------------------------------
-- The official API has no way to register a custom TearVariant; the standard
-- approach is:
--   1) Declare the entity in mod/content/entities2.xml:
--        <entity id="2" variant="600" name="MyCoolTear" anm2path="gfx/..."/>
--      (id=2 is EntityType.ENTITY_TEAR; variants start at 600 to stay clear of
--      the official 0~38 range)
--   2) Resolve the numeric variant with Isaac.GetEntityVariantByName("MyCoolTear")
--   3) tear:ChangeVariant(variant) switches the tear appearance (including
--      the custom anm2 animation)
-- This module manages the "module <-> variant" mapping and caches lookups.
-- ============================================================================

local Variants = {}

-- xmlName -> numeric variant
local byName = {}

-- effectId -> numeric variant
local byEffect = {}

-- numeric variant -> effectId (used to look up the owning module from
-- tear.Variant)
local byVariant = {}

-- Register: effectId is the module id, xmlName is the name attribute declared
-- in entities2.xml.
-- Returns: the numeric variant (success) or nil (not declared / game content
-- not loaded)
function Variants:register(effectId, xmlName)
    if byName[xmlName] then
        byEffect[effectId] = byName[xmlName]
        return byName[xmlName]
    end

    local variantId = Isaac.GetEntityVariantByName(xmlName)
    if variantId and variantId > 0 then
        byName[xmlName] = variantId
        byEffect[effectId] = variantId
        byVariant[variantId] = effectId
        return variantId
    end
    return nil
end

-- Query the variant assigned to a module
function Variants:getByEffect(effectId)
    return byEffect[effectId]
end

-- Look up the owning module by variant (nil when unowned)
function Variants:getOwner(variant)
    return byVariant[variant]
end

return Variants
