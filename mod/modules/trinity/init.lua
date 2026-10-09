-- Trinity
-- A reusable item module for Penitent Relics (design: docs/modules/trinity_design.md).
--
-- Player attacks cycle through three aspects (Father -> Son -> Spirit) using a
-- per-player counter. Each aspect tints the attack and has its own hit
-- behavior: Father applies a mark, Son deals bonus damage (more vs Father-marked
-- targets) and applies its own mark, Spirit deals bonus damage and unleashes
-- Judgment when the target carries both marks. Bombs are never affected.
-- All incidental damage goes through manager:dealDamage with a per-attack
-- channel so Trinity never blocks or recurses into other modules' damage.

local M = {
    id = "trinity",
    name = "Trinity",
    version = "2.7.3",
    description = "Attacks cycle through three aspects (Father, Son, Spirit). Applying all three marks to an enemy unleashes Judgment.",
    category = "item",
    config = {
        -- Passive stats. Soul hearts are fixed in items.xml, not runtime config.
        tearsBonus = 0.7,          -- flat tears-up added after item is acquired

        -- Tear modifiers
        fatherScale = 1.15,        -- Father tear visual scale
        sonDamageMult = 1.5,       -- Son tear damage multiplier
        spiritDamageMult = 2.0,    -- Spirit tear damage multiplier
        -- Mark system
        markDuration = 150,        -- mark lifetime in logical updates (~5s @ 30 Hz)
        sonMarkedDamageMult = 2.0, -- Son damage multiplier vs Father-marked targets
        markHeightPadding = 6,     -- extra vertical spacing above the target
        markLateralOffset = 8,     -- horizontal offset for the Son / Father icons
        markSizeRatio = 0.90,      -- icon size relative to target collision size
        markMinScale = 0.60,       -- minimum overhead-icon scale
        markMaxScale = 0.95,       -- maximum overhead-icon scale

        -- Judgment
        judgmentDamageMult = 5.0,  -- Spirit + dual-mark damage multiplier
        judgmentAoeDamageMult = 2.0,
        judgmentAoeRadius = 80,    -- pixels
        judgmentEffectFrames = 24, -- visual pillar duration
        judgmentSoundEnabled = true,
        judgmentSoundVolume = 0.90,
        judgmentSoundPitch = 1.00,

        -- Visual
        orbRadius = 28,            -- distance of orbiting light orbs from player center
        orbAngularSpeed = 0.04,    -- radians per frame
        laserTierTicks = 8,        -- active laser updates before the next aspect
        knifeTierTicks = 8,        -- active Mom's Knife updates before the next aspect
        laserMuzzleFrames = 38,    -- one normal Brimstone cycle; sustained beams repeat
        laserMuzzleScale = 1.10,
    },
}

local TIER_FATHER, TIER_SON, TIER_SPIRIT = 0, 1, 2

-- Base tints for the three aspects (tears, lasers, knives, orbs, emblems).
local TIER_COLORS = {
    Color(1.30, 1.18, 1.05, 1, 0.6, 0.55, 0.5),  -- Father: warm bright white
    Color(1.18, 0.92, 0.42, 1, 0.55, 0.4, 0.25), -- Son: gold / amber
    Color(0.72, 0.88, 1.25, 1, 0.4, 0.45, 0.6),  -- Spirit: ice blue
}

-- Laser colors need stronger separation because the native red beam otherwise
-- overwhelms subtle tints. The original sprite and beam geometry stay intact.
local LASER_TIER_COLORS = {
    Color(1.35, 1.25, 1.12, 1, 0.75, 0.68, 0.60), -- Father: ivory white
    Color(1.30, 0.86, 0.28, 1, 0.72, 0.42, 0.12), -- Son: amber gold
    Color(0.55, 0.94, 1.35, 1, 0.28, 0.62, 0.82), -- Spirit: ice cyan
}

-- A translucent, wider pass keeps the fine authored arcs readable over bright
-- beams without turning the muzzle into a solid opaque emblem.
local LASER_MUZZLE_GLOW_COLORS = {
    Color(1.35, 1.24, 1.10, 0.42, 0.85, 0.78, 0.68),
    Color(1.30, 0.82, 0.24, 0.42, 0.82, 0.48, 0.14),
    Color(0.48, 0.92, 1.38, 0.42, 0.34, 0.74, 0.96),
}

-- Prebuilt pulse colors enrich the original tear without replacing its sprite.
-- Four softly separated values are blended by SetColor over adjacent updates.
local TIER_PULSE_COLORS = {
    {
        Color(1.22, 1.13, 1.05, 1, 0.42, 0.38, 0.34),
        Color(1.30, 1.19, 1.08, 1, 0.56, 0.50, 0.44),
        Color(1.36, 1.24, 1.12, 1, 0.66, 0.60, 0.52),
        Color(1.29, 1.18, 1.07, 1, 0.53, 0.47, 0.41),
    },
    {
        Color(1.10, 0.82, 0.36, 1, 0.38, 0.25, 0.10),
        Color(1.18, 0.91, 0.43, 1, 0.52, 0.38, 0.18),
        Color(1.24, 0.98, 0.50, 1, 0.62, 0.48, 0.25),
        Color(1.17, 0.89, 0.41, 1, 0.49, 0.34, 0.16),
    },
    {
        Color(0.66, 0.81, 1.12, 1, 0.28, 0.34, 0.47),
        Color(0.73, 0.89, 1.24, 1, 0.40, 0.47, 0.62),
        Color(0.81, 0.97, 1.32, 1, 0.50, 0.57, 0.72),
        Color(0.72, 0.87, 1.21, 1, 0.37, 0.44, 0.59),
    },
}

-- Custom ANM2 paths; assets land in mod/resources/gfx/effects/ and are loaded
-- relative to the mod resource root (see docs/modules/trinity_assets.md).
local ORB_ANM2 = "gfx/effects/trinity_orb.anm2"
local FATHER_MARK_ANM2 = "gfx/effects/trinity_mark_father.anm2"
local SON_MARK_ANM2 = "gfx/effects/trinity_mark_son.anm2"
local JUDGMENT_ANM2 = "gfx/effects/trinity_judgment.anm2"
local JUDGMENT_RING_ANM2 = "gfx/effects/trinity_judgment_ring.anm2"
local LASER_MUZZLE_ANM2 = "gfx/effects/trinity_laser_muzzle.anm2"

-- All module visuals use a neutral custom effect variant. Native effect
-- variants such as POOF01 retain their engine behavior after Sprite:Load(),
-- so they cannot safely host persistent or manually-timed visuals.
local VISUAL_ENTITY_NAME = "Penitent Relics Trinity Visual"

-- GetData keys (AGENTS.md section 7: pr_<module_id>_<name>)
local KEY_COUNTER = "pr_trinity_counter"              -- player: next tier 0/1/2
local KEY_ORBS = "pr_trinity_orbs"                    -- player: {fatherPtr, sonPtr, spiritPtr}
local KEY_FATHER_MARK = "pr_trinity_father_mark"      -- enemy: mark expiry frame
local KEY_SON_MARK = "pr_trinity_son_mark"            -- enemy: mark expiry frame
local KEY_FATHER_ICON = "pr_trinity_father_icon"      -- enemy: EntityPtr of the overhead icon
local KEY_SON_ICON = "pr_trinity_son_icon"            -- enemy: EntityPtr of the overhead icon
local KEY_TIER = "pr_trinity_tier"                    -- attack entity: assigned tier 0/1/2
local KEY_LASER_VOLLEY = "pr_trinity_laser_volley"    -- direct owner: latest same-frame group
local KEY_LASER_GROUP = "pr_trinity_laser_group"      -- laser: shared dynamic tier state
local KEY_LASER_ROOT_HASH = "pr_trinity_laser_root_hash" -- laser: canonical damage channel
local KEY_LASER_HOMING_OWNED = "pr_trinity_laser_homing_owned"
local KEY_KNIFE_CLOCK_START = "pr_trinity_knife_clock_start" -- player: shared phase origin
local KEY_WINGS_APPLIED = "pr_trinity_wings_applied"  -- player: Revelation costume owned here

function M:cfg(key, fallback)
    return self.manager:getConfig(self, key, fallback)
end

function M:onRegister(manager)
    self.judgmentEffects = {}
    self.laserMuzzleEffects = {}
    self.activeLasers = {}
    self.sfx = SFXManager()
    self.itemId = Isaac.GetItemIdByName("Trinity")
    if not self.itemId or self.itemId < 1 then
        manager.Util.warn("Trinity registration failed: item name not found in content/items.xml")
        self.itemId = nil
        return
    end

    self.visualVariant = Isaac.GetEntityVariantByName(VISUAL_ENTITY_NAME)
    if not self.visualVariant or self.visualVariant < 1 then
        manager.Util.warn("Trinity visual entity is missing from content/entities2.xml; "
            .. "using EFFECT_NULL fallback")
        self.visualVariant = EffectVariant.EFFECT_NULL
    end

    self.wingCostume = Isaac.GetItemConfig():GetCollectible(
        CollectibleType.COLLECTIBLE_REVELATION
    )
    if not self.wingCostume then
        manager.Util.warn("Trinity could not resolve the Revelation wing costume")
    end

    manager.Util.log("Trinity ready, runtime ID=" .. tostring(self.itemId))
    Isaac.DebugString("[PenitentRelics] Trinity ready: giveitem c" .. tostring(self.itemId))

    -- The native pickup prompt carries only the thematic sentence (like most
    -- vanilla Q4 angel items); EID (External Item Descriptions) shows the full
    -- mechanic breakdown. EID rewrites RegisterMod, so its mod context is
    -- already "Penitent Relics" when this runs. Missing EID falls back silently to
    -- the short native description.
    if EID and EID.addCollectible then
        EID:addCollectible(self.itemId,
            "↑ +3 Soul Hearts, Flight, +0.7 Tears\n\n"
            .. "Tears cycle: Father → Son → Spirit\n"
            .. "Father: applies Father's Mark on hit (5s)\n"
            .. "Son: pierces, 1.5x damage; 3x on Marked foes, applies Son's Mark (5s)\n"
            .. "Spirit: homes, 2x damage\n"
            .. "⚡ Judgment: Spirit on a doubly-marked foe → 5x damage, 2x AOE splash, clears all marks",
            "Trinity",
            "en_us")
    end
end

function M:spawnVisual(position, spawner, anm2Path, animation)
    local visual = Isaac.Spawn(
        EntityType.ENTITY_EFFECT,
        self.visualVariant,
        0,
        position,
        Vector.Zero,
        spawner
    )
    local effect = visual and visual:ToEffect() or nil
    if not effect then
        if visual and visual:Exists() then
            visual:Remove()
        end
        self.manager.Util.warn("Trinity failed to spawn custom visual: " .. anm2Path)
        return nil
    end

    effect.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    effect.GridCollisionClass = GridCollisionClass.COLLISION_NONE
    effect:SetTimeout(-1)
    local sprite = effect:GetSprite()
    sprite:Load(anm2Path, true)
    sprite:Play(animation or "Idle", true)
    return effect
end

-- ---------------------------------------------------------------------------
-- Stats: flight and tears bonus (MC_EVALUATE_CACHE)
-- ---------------------------------------------------------------------------
function M:onEvaluateCache(player, cacheFlag)
    if not self.itemId or not player then
        return
    end
    if not player:HasCollectible(self.itemId) then
        return
    end
    if cacheFlag == CacheFlag.CACHE_FLYING then
        player.CanFly = true
    elseif cacheFlag == CacheFlag.CACHE_FIREDELAY then
        -- Tears are converted via fire delay so +0.7 tears is not a flat
        -- MaxFireDelay subtraction (docs/modules/trinity_design.md section 4.1).
        local bonus = self:cfg("tearsBonus", 0.7)
        if bonus > 0 then
            local currentTears = 30 / (player.MaxFireDelay + 1)
            player.MaxFireDelay = math.max(0, 30 / (currentTears + bonus) - 1)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Per-player tier counter (0 = Father, 1 = Son, 2 = Spirit)
-- ---------------------------------------------------------------------------
function M:getCounter(player)
    local data = player:GetData()
    local counter = data[KEY_COUNTER]
    if type(counter) ~= "number" or counter < TIER_FATHER or counter > TIER_SPIRIT then
        counter = TIER_FATHER
        data[KEY_COUNTER] = counter
    end
    return counter
end

function M:advanceCounter(player)
    local next = (self:getCounter(player) + 1) % 3
    player:GetData()[KEY_COUNTER] = next
    return next
end

-- ---------------------------------------------------------------------------
-- Tier assignment: idempotent per attack entity, so the Fire/Init callback and
-- the first-frame Update fallback can both run without advancing twice.
-- ---------------------------------------------------------------------------
function M:assignTier(attack, player)
    local data = attack:GetData()
    local tier = data[KEY_TIER]
    if type(tier) == "number" then
        return tier
    end
    tier = self:getCounter(player)
    data[KEY_TIER] = tier
    self:advanceCounter(player)
    return tier
end

function M:applyTearAspect(tear, tier)
    -- Keep the original sprite so directional animations and special variants
    -- remain fully compatible; Trinity only owns its color treatment.
    tear:SetColor(TIER_COLORS[tier + 1], -1, 100, false, false)
    if tier == TIER_SON then
        tear:AddTearFlags(TearFlags.TEAR_PIERCING)
    elseif tier == TIER_SPIRIT then
        tear:AddTearFlags(TearFlags.TEAR_HOMING)
    elseif tier == TIER_FATHER then
        local sprite = tear:GetSprite()
        sprite.Scale = sprite.Scale * self:cfg("fatherScale", 1.15)
    end
end

-- Short fade frames keep the color on lasers/knives without permanently
-- fighting other mods' SetColor calls.
function M:applyWeaponColor(entity, tier)
    entity:SetColor(TIER_COLORS[tier + 1], 2, 100, false, false)
end

-- ---------------------------------------------------------------------------
-- Tears
-- ---------------------------------------------------------------------------
function M:onFireTear(tear, ctx)
    local player = ctx.player
    if not player or not player:HasCollectible(self.itemId) then
        return
    end
    local tier = self:assignTier(tear, player)
    if type(tier) == "number" then
        self:applyTearAspect(tear, tier)
    end
end

function M:onTearUpdate(tear, ctx)
    local data = tear:GetData()
    local player = ctx.player
    if not player or not player:HasCollectible(self.itemId) then
        return
    end
    local tier = data[KEY_TIER]
    if type(tier) ~= "number" then
        -- First-frame fallback for tears that never passed through onFireTear;
        -- assignTier is idempotent so this never advances the counter twice.
        tier = self:assignTier(tear, player)
        if type(tier) ~= "number" then
            return
        end
        self:applyTearAspect(tear, tier)
    end
    if tear.FrameCount % 3 == 0 then
        local palette = TIER_PULSE_COLORS[tier + 1]
        local colorIndex = (math.floor(tear.FrameCount / 3) + tier) % #palette + 1
        tear:SetColor(palette[colorIndex], 4, 100, false, false)
    end
end

-- ---------------------------------------------------------------------------
-- Lasers: sibling roots created by one volley share a dynamic aspect. The
-- aspect advances every laserTierTicks logical updates, so persistent beams
-- keep cycling. Child, bounce and sample lasers inherit the root group and its
-- damage channel instead of consuming extra counter slots.
-- ---------------------------------------------------------------------------
function M:findLaserRoot(laser)
    local root = laser
    for _ = 1, 8 do
        local parent = root.Parent
        if not parent or parent.Type ~= EntityType.ENTITY_LASER then
            parent = root.SpawnerEntity
        end
        if not parent or parent.Type ~= EntityType.ENTITY_LASER then
            break
        end
        root = parent
    end
    return root
end

function M:getLaserOwner(root, player)
    local parent = root.Parent
    if parent and parent.Type ~= EntityType.ENTITY_LASER and parent.GetData then
        return parent
    end
    local spawner = root.SpawnerEntity
    if spawner and spawner.Type ~= EntityType.ENTITY_LASER and spawner.GetData then
        return spawner
    end
    return player
end

function M:createLaserGroup(root, player)
    local frame = Game():GetFrameCount()
    local owner = self:getLaserOwner(root, player)
    local ownerData = owner and owner:GetData() or nil
    local group = ownerData and ownerData[KEY_LASER_VOLLEY] or nil

    if type(group) ~= "table" or group.bornFrame ~= frame then
        group = {
            bornFrame = frame,
            block = 0,
            tier = self:getCounter(player),
            muzzlePlayed = false,
        }
        self:advanceCounter(player)
        if ownerData then
            ownerData[KEY_LASER_VOLLEY] = group
        end
    end

    root:GetData()[KEY_LASER_GROUP] = group
    return group
end

function M:spawnLaserMuzzle(root, group)
    if type(group) ~= "table" or group.muzzlePlayed then
        return
    end
    group.muzzlePlayed = true

    local sprite = Sprite()
    sprite:Load(LASER_MUZZLE_ANM2, true)
    sprite:Play("Pulse", true)
    local scale = self:cfg("laserMuzzleScale", 1.10)
    sprite.Scale = Vector(scale, scale)
    sprite.Color = LASER_TIER_COLORS[group.tier + 1]
    self.laserMuzzleEffects[#self.laserMuzzleEffects + 1] = {
        sprite = sprite,
        rootPtr = EntityPtr(root),
        born = Game():GetFrameCount(),
        frames = self:cfg("laserMuzzleFrames", 10),
    }
end

function M:getLaserSampleStart(root)
    if not root.GetSamples then
        return nil
    end

    local ok, sample = pcall(function()
        local samples = root:GetSamples()
        if not samples or #samples < 1 then
            return nil
        end
        return samples:Get(0)
    end)
    if not ok or not sample or not sample.Distance then
        return nil
    end

    -- Some modded lasers expose relative or stale samples. Only accept a point
    -- near the entity origin so a malformed path cannot render in a room corner.
    if sample:Distance(root.Position) > 96 then
        return nil
    end
    return sample
end

function M:getLaserMuzzlePosition(root)
    local isCircle = root.IsCircleLaser and root:IsCircleLaser()
    if isCircle then
        -- Tech X and the other circular laser subtypes store their rendered
        -- center directly in Position. Their PositionOffset belongs to the
        -- laser sprite and is not a mouth-origin adjustment; applying it here
        -- shifts the Trinity pulse away from the native ring.
        return root.Position
    end

    local position = nil
    position = self:getLaserSampleStart(root)
    if not position then
        position = root.Position + (root.ParentOffset or Vector.Zero)
    end

    -- Laser samples are logical world positions. Brimstone moves its visible
    -- beam from the player's floor origin to the mouth with PositionOffset.
    position = position + (root.PositionOffset or Vector.Zero)

    return position
end

function M:refreshLaserGroup(group, player)
    local ticks = math.max(1, math.floor(self:cfg("laserTierTicks", 8)))
    local elapsed = math.max(0, Game():GetFrameCount() - group.bornFrame)
    local block = math.floor(elapsed / ticks)
    while group.block < block do
        group.tier = self:getCounter(player)
        self:advanceCounter(player)
        group.block = group.block + 1
    end
    return group.tier
end

function M:applyLaserAspect(laser, tier)
    local data = laser:GetData()
    laser:SetColor(LASER_TIER_COLORS[tier + 1], 2, 100, false, false)

    if tier == TIER_SPIRIT then
        if not laser:HasTearFlags(TearFlags.TEAR_HOMING) then
            laser:AddTearFlags(TearFlags.TEAR_HOMING)
            data[KEY_LASER_HOMING_OWNED] = true
        end
    elseif data[KEY_LASER_HOMING_OWNED] then
        laser:ClearTearFlags(TearFlags.TEAR_HOMING)
        data[KEY_LASER_HOMING_OWNED] = nil
    end
end

function M:assignOrInheritLaserTier(laser, player, allowRootAssignment)
    local root = self:findLaserRoot(laser)
    local rootData = root:GetData()
    local group = rootData[KEY_LASER_GROUP]

    if type(group) ~= "table" then
        if root ~= laser then
            group = self:createLaserGroup(root, player)
        elseif not allowRootAssignment then
            return nil
        else
            group = self:createLaserGroup(root, player)
        end
    end

    local tier = self:refreshLaserGroup(group, player)
    local data = laser:GetData()
    data[KEY_LASER_GROUP] = group
    data[KEY_LASER_ROOT_HASH] = GetPtrHash(root)
    data[KEY_TIER] = tier
    rootData[KEY_LASER_ROOT_HASH] = GetPtrHash(root)
    rootData[KEY_TIER] = tier
    return tier
end

function M:trackActiveLaser(laser, player)
    local root = self:findLaserRoot(laser)
    local group = root:GetData()[KEY_LASER_GROUP]
    if type(group) ~= "table" then
        return
    end
    self.activeLasers[GetPtrHash(root)] = {
        ptr = EntityPtr(root),
        playerPtr = EntityPtr(player),
        groupBorn = group.bornFrame,
        lastSeen = Game():GetFrameCount(),
    }
end

function M:findActiveLaser(player)
    local frame = Game():GetFrameCount()
    local playerHash = GetPtrHash(player)
    local newestRoot = nil
    local newestBorn = -1

    for hash, entry in pairs(self.activeLasers) do
        local root = entry.ptr and entry.ptr.Ref or nil
        local owner = entry.playerPtr and entry.playerPtr.Ref or nil
        if not root or not root:Exists() or frame > entry.lastSeen + 1 then
            self.activeLasers[hash] = nil
        elseif owner and owner:Exists() and GetPtrHash(owner) == playerHash
            and entry.groupBorn >= newestBorn then
            newestRoot = root
            newestBorn = entry.groupBorn
        end
    end
    return newestRoot
end

function M:onLaserInit(laser, ctx)
    local player = ctx.player
    if not player or not player:HasCollectible(self.itemId) then
        return
    end
    -- Technology can deal its one-hit damage before the first LaserUpdate.
    -- Assign and track the root now, but defer tear flags and muzzle placement
    -- until Update because those fields can still be incomplete during Init.
    local tier = self:assignOrInheritLaserTier(laser, player, true)
    if type(tier) == "number" then
        laser:SetColor(LASER_TIER_COLORS[tier + 1], 2, 100, false, false)
        self:trackActiveLaser(laser, player)
    end
end

function M:onLaserUpdate(laser, ctx)
    local player = ctx.player
    if not player or not player:HasCollectible(self.itemId) then
        local data = laser:GetData()
        if data[KEY_LASER_HOMING_OWNED] then
            laser:ClearTearFlags(TearFlags.TEAR_HOMING)
            data[KEY_LASER_HOMING_OWNED] = nil
        end
        return
    end
    local tier = self:assignOrInheritLaserTier(laser, player, true)
    if type(tier) == "number" then
        local root = self:findLaserRoot(laser)
        self:spawnLaserMuzzle(root, root:GetData()[KEY_LASER_GROUP])
        self:applyLaserAspect(laser, tier)
        self:trackActiveLaser(laser, player)
    end
end

-- ---------------------------------------------------------------------------
-- Mom's Knife: every knife owned by one Trinity holder reads the same player
-- clock. No knife subtype, movement state or synergy-specific grouping is
-- needed, so master, returning and Brimstone-generated knives stay synchronized.
-- ---------------------------------------------------------------------------
function M:assignSharedKnifeTier(knife, player)
    local frame = Game():GetFrameCount()
    local ownerData = player:GetData()
    local clockStart = ownerData[KEY_KNIFE_CLOCK_START]
    if type(clockStart) ~= "number" then
        clockStart = frame
        ownerData[KEY_KNIFE_CLOCK_START] = clockStart
    end

    local ticks = math.max(1, math.floor(self:cfg("knifeTierTicks", 8)))
    local tier = math.floor(math.max(0, frame - clockStart) / ticks) % 3
    knife:GetData()[KEY_TIER] = tier
    return tier
end

function M:onKnifeUpdate(knife, ctx)
    local player = ctx.player
    if not player or not player:HasCollectible(self.itemId) then
        player = self.manager:findPlayerWithCollectible(self.itemId)
        if not player then
            return
        end
    end
    local tier = self:assignSharedKnifeTier(knife, player)
    self:applyWeaponColor(knife, tier)
end

-- ---------------------------------------------------------------------------
-- Marks: each enemy tracks Father and Son marks with independent expiry
-- frames (logical clock, paused-safe). Marks refresh on repeat hits.
-- ---------------------------------------------------------------------------
function M:hasFatherMark(entity, frame)
    local expiry = entity:GetData()[KEY_FATHER_MARK]
    return type(expiry) == "number" and frame < expiry
end

function M:hasSonMark(entity, frame)
    local expiry = entity:GetData()[KEY_SON_MARK]
    return type(expiry) == "number" and frame < expiry
end

local function iconAlive(ptr)
    return ptr ~= nil and ptr.Ref ~= nil and ptr.Ref:Exists()
end

function M:spawnMarkIcon(target, anm2Path)
    local mark = self:spawnVisual(target.Position, target, anm2Path)
    if not mark then
        return nil
    end
    mark.DepthOffset = 100
    return EntityPtr(mark)
end

function M:removeMarkIcon(ptr)
    local icon = ptr and ptr.Ref or nil
    if icon and icon:Exists() then
        icon:Remove()
    end
end

function M:applyFatherMark(entity, frame)
    local data = entity:GetData()
    data[KEY_FATHER_MARK] = frame + self:cfg("markDuration", 150)
    if not iconAlive(data[KEY_FATHER_ICON]) then
        data[KEY_FATHER_ICON] = self:spawnMarkIcon(entity, FATHER_MARK_ANM2)
    end
end

function M:applySonMark(entity, frame)
    local data = entity:GetData()
    data[KEY_SON_MARK] = frame + self:cfg("markDuration", 150)
    if not iconAlive(data[KEY_SON_ICON]) then
        data[KEY_SON_ICON] = self:spawnMarkIcon(entity, SON_MARK_ANM2)
    end
end

function M:clearAllMarks(entity)
    local data = entity:GetData()
    data[KEY_FATHER_MARK] = nil
    data[KEY_SON_MARK] = nil
    self:removeMarkIcon(data[KEY_FATHER_ICON])
    data[KEY_FATHER_ICON] = nil
    self:removeMarkIcon(data[KEY_SON_ICON])
    data[KEY_SON_ICON] = nil
end

-- Follow the target overhead: Father icon sits left, Son icon right, so the
-- two never overlap on a doubly-marked enemy.
function M:updateMarkIcon(iconPtr, target, rightSide)
    local icon = iconPtr and iconPtr.Ref or nil
    if not icon or not icon:Exists() then
        return
    end
    icon.Position = target.Position
    icon.Velocity = Vector.Zero
    local entityScale = target.SpriteScale or Vector(1, 1)
    local visualScale = math.max(math.abs(entityScale.X), math.abs(entityScale.Y))
    local targetSize = math.max((target.Size or 20) * visualScale, 8)
    local scale = targetSize * self:cfg("markSizeRatio", 0.90) / 32
    scale = math.max(
        self:cfg("markMinScale", 0.60),
        math.min(scale, self:cfg("markMaxScale", 0.95))
    )
    icon.SpriteScale = Vector(scale, scale)
    local lateral = self:cfg("markLateralOffset", 8)
    if not rightSide then
        lateral = -lateral
    end
    local height = targetSize + self:cfg("markHeightPadding", 6)
    local targetOffset = target.SpriteOffset or Vector.Zero
    icon.SpriteOffset = targetOffset + Vector(lateral, -height)
    icon.DepthOffset = (target.DepthOffset or 0) + 10
end

-- ---------------------------------------------------------------------------
-- Incidental damage: sourced from the player (not the attack entity) so the
-- buffered hit cannot re-enter Trinity's onAttackHit next logical frame, and
-- channeled per attack entity so different players/attacks settle in the same
-- frame while the same attack on the same target stays locked.
-- ---------------------------------------------------------------------------
function M:dealIncidental(target, amount, player, attackEntity)
    local attackData = attackEntity:GetData()
    local channelHash = attackData[KEY_LASER_ROOT_HASH] or GetPtrHash(attackEntity)
    local channel = self.id .. ":" .. tostring(channelHash)
    return self.manager:dealDamage(target, amount, 0, EntityRef(player), channel)
end

-- ---------------------------------------------------------------------------
-- Judgment: Spirit hits a dual-marked target. The main target's total hit
-- damage reaches judgmentDamageMult x the original amount (only the delta is
-- dealt here); other vulnerable enemies in radius take a flat AOE hit. The
-- main target does not receive the AOE damage twice.
-- ---------------------------------------------------------------------------
function M:triggerJudgment(target, player, amount, attackEntity)
    local extra = amount * (self:cfg("judgmentDamageMult", 5.0) - 1.0)
    if extra > 0 then
        self:dealIncidental(target, extra, player, attackEntity)
    end

    local aoeMult = self:cfg("judgmentAoeDamageMult", 2.0)
    local radius = self:cfg("judgmentAoeRadius", 80)
    if aoeMult > 0 and radius > 0 then
        local aoeDamage = amount * aoeMult
        local targetHash = GetPtrHash(target)
        local targetPosition = target.Position
        local entities = Isaac.GetRoomEntities()
        for i = 1, #entities do
            local other = entities[i]
            if other
                and GetPtrHash(other) ~= targetHash
                and other:IsEnemy() and not other:IsDead()
                and other:IsVulnerableEnemy()
                and not other:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
                and other.Position:Distance(targetPosition) <= radius then
                self:dealIncidental(other, aoeDamage, player, attackEntity)
            end
        end
    end

    self:playJudgmentSound()
    self:playJudgmentEffects(target)
    self:clearAllMarks(target)
end

function M:playJudgmentSound()
    if not self:cfg("judgmentSoundEnabled", true) then
        return
    end
    local volume = math.max(0, self:cfg("judgmentSoundVolume", 0.90))
    local pitch = math.max(0.01, self:cfg("judgmentSoundPitch", 1.00))
    -- SOUND_ANGEL_BEAM is the native angelic beam impact. A six-frame replay
    -- window prevents simultaneous co-op Judgments from clipping each other.
    self.sfx:Play(SoundEffect.SOUND_ANGEL_BEAM, volume, 6, false, pitch, 0)
end

function M:playJudgmentEffects(target)
    local frame = Game():GetFrameCount()
    local frames = self:cfg("judgmentEffectFrames", 24)
    local effects = self.judgmentEffects

    local pillar = self:spawnVisual(target.Position, target, JUDGMENT_ANM2)
    if pillar then
        pillar.DepthOffset = (target.DepthOffset or 0) + 100
        effects[#effects + 1] = {
            ptr = EntityPtr(pillar), kind = "pillar", born = frame, frames = frames,
        }
    end

    local ring = self:spawnVisual(target.Position, target, JUDGMENT_RING_ANM2)
    if ring then
        ring.DepthOffset = (target.DepthOffset or 0) - 10
        effects[#effects + 1] = {
            ptr = EntityPtr(ring), kind = "ring", born = frame, frames = frames,
        }
    end
end

function M:clearJudgmentEffects()
    for i = #self.judgmentEffects, 1, -1 do
        local entry = self.judgmentEffects[i]
        local effect = entry.ptr and entry.ptr.Ref or nil
        if effect and effect:Exists() then
            effect:Remove()
        end
        table.remove(self.judgmentEffects, i)
    end
end

function M:updateJudgmentEffects(frame)
    for i = #self.judgmentEffects, 1, -1 do
        local entry = self.judgmentEffects[i]
        local fx = entry.ptr and entry.ptr.Ref or nil
        if not fx or not fx:Exists() then
            table.remove(self.judgmentEffects, i)
        elseif frame >= entry.born + entry.frames then
            fx:Remove()
            table.remove(self.judgmentEffects, i)
        end
    end
end

function M:clearLaserMuzzleEffects()
    for i = #self.laserMuzzleEffects, 1, -1 do
        table.remove(self.laserMuzzleEffects, i)
    end
end

function M:updateLaserMuzzleEffects(frame)
    for i = #self.laserMuzzleEffects, 1, -1 do
        local entry = self.laserMuzzleEffects[i]
        local root = entry.rootPtr and entry.rootPtr.Ref or nil
        if not root or not root:Exists() then
            table.remove(self.laserMuzzleEffects, i)
        elseif frame >= entry.born + entry.frames then
            -- Normal Brimstone expires at this boundary. Persistent lasers are
            -- still alive and receive a new authored 38-frame pulse cycle.
            entry.born = frame
            entry.sprite:Play("Pulse", true)
        else
            local tier = root:GetData()[KEY_TIER]
            if type(tier) == "number" then
                entry.sprite.Color = LASER_TIER_COLORS[tier + 1]
            end
            entry.sprite:Update()
        end
    end
end

function M:renderLaserMuzzle(entry, root, position)
    local elapsed = math.max(0, Game():GetFrameCount() - entry.born)
    local duration = math.max(1, entry.frames - 1)
    local progress = math.min(1, elapsed / duration)
    local breath = math.sin(progress * math.pi)
    local baseScale = self:cfg("laserMuzzleScale", 1.10)
    local coreScale = baseScale * (1 + 0.16 * breath)
    local tier = root:GetData()[KEY_TIER]
    if type(tier) ~= "number" then
        tier = TIER_FATHER
    end

    entry.sprite.Rotation = -7 + 14 * progress
    entry.sprite.Scale = Vector(coreScale * 1.34, coreScale * 1.34)
    entry.sprite.Color = LASER_MUZZLE_GLOW_COLORS[tier + 1]
    entry.sprite:Render(position, Vector.Zero, Vector.Zero)

    entry.sprite.Scale = Vector(coreScale, coreScale)
    entry.sprite.Color = LASER_TIER_COLORS[tier + 1]
    entry.sprite:Render(position, Vector.Zero, Vector.Zero)
end

function M:onLaserRender(laser, offset, ctx)
    if not laser.IsCircleLaser or not laser:IsCircleLaser() then
        return
    end

    local laserHash = GetPtrHash(laser)
    for i = 1, #self.laserMuzzleEffects do
        local entry = self.laserMuzzleEffects[i]
        local root = entry.rootPtr and entry.rootPtr.Ref or nil
        if root and root:Exists() and GetPtrHash(root) == laserHash then
            -- Circular lasers have an additional per-render displacement that
            -- is available only in MC_POST_LASER_RENDER. Drawing in this same
            -- coordinate path keeps the Trinity pulse locked to Tech X while
            -- it travels, homes, or is affected by render interpolation.
            local position = Isaac.WorldToScreen(laser.Position)
                + (offset or Vector.Zero)
            self:renderLaserMuzzle(entry, root, position)
            return
        end
    end
end

function M:onRender()
    for i = 1, #self.laserMuzzleEffects do
        local entry = self.laserMuzzleEffects[i]
        local root = entry.rootPtr and entry.rootPtr.Ref or nil
        local isCircle = root and root.IsCircleLaser and root:IsCircleLaser()
        if root and root:Exists() and not isCircle then
            local position = Isaac.WorldToScreen(self:getLaserMuzzlePosition(root))
            self:renderLaserMuzzle(entry, root, position)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Hit resolution (MC_ENTITY_TAKE_DMG -> onAttackHit)
-- ---------------------------------------------------------------------------
function M:onAttackHit(target, amount, damageFlags, source, countdownFrames, ctx)
    if not self.itemId then
        return
    end
    if not target or not target:IsEnemy() or target:IsDead()
        or not target:IsVulnerableEnemy() then
        return
    end
    if target:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
        return
    end
    if not ctx then
        return
    end
    -- Bombs are intentionally excluded: no tier, no marks, no Judgment.
    if ctx.type ~= "tear" and ctx.type ~= "laser" and ctx.type ~= "knife" then
        return
    end
    local player = ctx.player
    if not player or not player:HasCollectible(self.itemId) then
        -- EntityRef can lose its entity pointer while retaining SpawnerType.
        -- Falling back to a holder also supports the common single-player case.
        player = self.manager:findPlayerWithCollectible(self.itemId)
    end
    if not player then
        return
    end

    local attackEntity = ctx.entity
    if ctx.type == "laser"
        and (not attackEntity or attackEntity.Type ~= EntityType.ENTITY_LASER) then
        attackEntity = self:findActiveLaser(player)
    end
    if not attackEntity then
        return
    end

    local tier
    if ctx.type == "laser" then
        -- Damage can be evaluated before this frame's PostLaserUpdate. Refresh
        -- here as well so the 8-tick boundary changes behavior and color in the
        -- same logical frame.
        tier = self:assignOrInheritLaserTier(attackEntity, player, true)
    elseif ctx.type == "knife" then
        tier = self:assignSharedKnifeTier(attackEntity, player)
    else
        tier = attackEntity:GetData()[KEY_TIER]
    end
    if type(tier) ~= "number" then
        return
    end

    local frame = Game():GetFrameCount()
    if tier == TIER_FATHER then
        self:applyFatherMark(target, frame)
    elseif tier == TIER_SON then
        local mult = self:cfg("sonDamageMult", 1.5)
        if self:hasFatherMark(target, frame) then
            mult = mult * self:cfg("sonMarkedDamageMult", 2.0)
            self:applySonMark(target, frame)
        end
        local extra = amount * (mult - 1.0)
        if extra > 0 then
            self:dealIncidental(target, extra, player, attackEntity)
        end
    elseif tier == TIER_SPIRIT then
        if self:hasFatherMark(target, frame) and self:hasSonMark(target, frame) then
            self:triggerJudgment(target, player, amount, attackEntity)
        else
            local extra = amount * (self:cfg("spiritDamageMult", 2.0) - 1.0)
            if extra > 0 then
                self:dealIncidental(target, extra, player, attackEntity)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Orbiting light orbs (pure decoration, no collision)
-- ---------------------------------------------------------------------------
function M:updateOrbs(player, frame)
    local data = player:GetData()
    local orbs = data[KEY_ORBS]
    if not orbs then
        orbs = { nil, nil, nil }
        data[KEY_ORBS] = orbs
    end

    local radius = self:cfg("orbRadius", 28)
    local speed = self:cfg("orbAngularSpeed", 0.04)
    for tier = TIER_FATHER, TIER_SPIRIT do
        local ptr = orbs[tier + 1]
        local orb = ptr and ptr.Ref or nil
        if not orb or not orb:Exists() then
            orb = self:spawnVisual(player.Position, player, ORB_ANM2)
            if orb then
                orb.DepthOffset = (player.DepthOffset or 0) + 10
                -- Slightly different playback rates keep the three hand-drawn
                -- breathing loops from locking into the same silhouette.
                orb:GetSprite().PlaybackSpeed = 0.90 + tier * 0.10
                orbs[tier + 1] = EntityPtr(orb)
            end
        end
        if orb then
            -- Decreasing angle = counterclockwise on screen; each orb starts
            -- 120 degrees apart so the three aspects stay evenly spaced.
            local phase = tier * (math.pi * 2 / 3) - frame * speed
            local depth = (math.sin(phase) + 1.0) * 0.5
            local breathingRadius = radius + math.sin(frame * 0.055 + tier * 2.0) * 1.0
            local bob = math.sin(frame * 0.09 + tier * 2.1) * 1.2
            orb.Position = player.Position + Vector(
                math.cos(phase) * breathingRadius,
                math.sin(phase) * breathingRadius * 0.62 + bob
            )
            orb.Velocity = Vector.Zero
            local perspectiveScale = 0.86 + depth * 0.10
            orb.SpriteScale = Vector(perspectiveScale, perspectiveScale)
            orb.DepthOffset = (player.DepthOffset or 0) + (depth > 0.5 and 18 or -6)
            self:applyWeaponColor(orb, tier)
        end
    end
end

function M:updateWingCostume(player, enabled)
    if not self.wingCostume then
        return
    end
    local data = player:GetData()
    if enabled and not data[KEY_WINGS_APPLIED] then
        player:AddCostume(self.wingCostume, false)
        data[KEY_WINGS_APPLIED] = true
    elseif not enabled and data[KEY_WINGS_APPLIED] then
        player:RemoveCostume(self.wingCostume)
        data[KEY_WINGS_APPLIED] = nil
    end
end

function M:removeOrbs(data)
    local orbs = data[KEY_ORBS]
    if orbs then
        for i = 1, #orbs do
            local ptr = orbs[i]
            local orb = ptr and ptr.Ref or nil
            if orb and orb:Exists() then
                orb:Remove()
            end
        end
        data[KEY_ORBS] = nil
    end
end

-- ---------------------------------------------------------------------------
-- Lifecycle: room/game resets
-- ---------------------------------------------------------------------------
function M:onGameStart(continued)
    -- A new run must not keep tracking visuals from a previous run.
    self:clearJudgmentEffects()
    self:clearLaserMuzzleEffects()
    self.activeLasers = {}
    self:resetRunState(true)
end

function M:onNewRoom()
    -- Marks are room-scoped; the rotation restarts per room so every room
    -- begins with Father (docs/modules/trinity_design.md section 5.2).
    self:clearJudgmentEffects()
    self:clearLaserMuzzleEffects()
    self.activeLasers = {}
    self:resetRunState(false)
end

function M:resetRunState(removeOrbs)
    for i = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player then
            local data = player:GetData()
            data[KEY_COUNTER] = 0
            data[KEY_LASER_VOLLEY] = nil
            data[KEY_KNIFE_CLOCK_START] = nil
            if removeOrbs then
                self:removeOrbs(data)
                self:updateWingCostume(player, false)
            end
        end
    end
    local entities = Isaac.GetRoomEntities()
    for i = 1, #entities do
        local entity = entities[i]
        if entity and entity:IsEnemy() then
            self:clearAllMarks(entity)
        end
    end
end

function M:onUpdate()
    if not self.itemId then
        return
    end

    local frame = Game():GetFrameCount()
    local hasHolder = self.manager:anyPlayerHasCollectible(self.itemId)
    if hasHolder then
        self:updateJudgmentEffects(frame)
        self:updateLaserMuzzleEffects(frame)
    else
        self:clearJudgmentEffects()
        self:clearLaserMuzzleEffects()
    end

    local entities = Isaac.GetRoomEntities()
    for i = 1, #entities do
        local entity = entities[i]
        local data = entity and entity:GetData() or nil
        if entity and entity:IsEnemy() then
            if not hasHolder or entity:IsDead() then
                -- Marks cannot outlive their owner item or their enemy.
                self:clearAllMarks(entity)
            else
                local father = data[KEY_FATHER_MARK]
                if type(father) == "number" and frame >= father then
                    data[KEY_FATHER_MARK] = nil
                    self:removeMarkIcon(data[KEY_FATHER_ICON])
                    data[KEY_FATHER_ICON] = nil
                end
                local son = data[KEY_SON_MARK]
                if type(son) == "number" and frame >= son then
                    data[KEY_SON_MARK] = nil
                    self:removeMarkIcon(data[KEY_SON_ICON])
                    data[KEY_SON_ICON] = nil
                end
                if data[KEY_FATHER_ICON] then
                    self:updateMarkIcon(data[KEY_FATHER_ICON], entity, false)
                end
                if data[KEY_SON_ICON] then
                    self:updateMarkIcon(data[KEY_SON_ICON], entity, true)
                end
            end
        end
    end

    for i = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player then
            local active = player:HasCollectible(self.itemId) and not player:IsDead()
            self:updateWingCostume(player, active)
            if active then
                self:updateOrbs(player, frame)
            else
                player:GetData()[KEY_KNIFE_CLOCK_START] = nil
                self:removeOrbs(player:GetData())
            end
        end
    end
end

return M
