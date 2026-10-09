-- Lightweight regression test for the Trinity state machine.
-- Run from the repository root with: tools\lua\lua53.exe tests\test_trinity.lua

local function vector(x, y)
    local value = { X = x, Y = y }
    local mt = {}
    function mt.__add(a, b) return vector(a.X + b.X, a.Y + b.Y) end
    function mt.__sub(a, b) return vector(a.X - b.X, a.Y - b.Y) end
    function mt.__mul(a, b)
        if type(a) == "number" then return vector(a * b.X, a * b.Y) end
        return vector(a.X * b, a.Y * b)
    end
    function value:Length() return math.sqrt(self.X * self.X + self.Y * self.Y) end
    function value:Normalized()
        local length = self:Length()
        return vector(self.X / length, self.Y / length)
    end
    function value:Dot(other) return self.X * other.X + self.Y * other.Y end
    function value:Distance(other)
        return math.sqrt((self.X - other.X) ^ 2 + (self.Y - other.Y) ^ 2)
    end
    return setmetatable(value, mt)
end

Vector = setmetatable({ Zero = vector(0, 0) }, {
    __call = function(_, x, y) return vector(x, y) end,
})
Color = function(...) return { ... } end
EntityRef = function(entity) return { Entity = entity } end
EntityPtr = function(entity) return { Ref = entity } end
GetPtrHash = function(entity) return entity.ptrHash or entity.InitSeed end

EntityType = {
    ENTITY_PLAYER = 1,
    ENTITY_TEAR = 2,
    ENTITY_BOMBDROP = 4,
    ENTITY_LASER = 7,
    ENTITY_KNIFE = 8,
    ENTITY_EFFECT = 1000,
}
EffectVariant = { EFFECT_NULL = 0, POOF01 = 15 }
CollectibleType = { COLLECTIBLE_REVELATION = 643 }
TearFlags = { TEAR_PIERCING = 1 << 0, TEAR_HOMING = 1 << 1 }
WeaponType = {
    WEAPON_TEARS = 1,
    WEAPON_LASER = 2,
    WEAPON_KNIFE = 3,
    WEAPON_BOMBS = 4,
}
DamageFlag = { DAMAGE_LASER = 1 << 3 }
CacheFlag = { CACHE_FIREDELAY = 1 << 1, CACHE_FLYING = 1 << 7 }
EntityFlag = { FLAG_FRIENDLY = 1 << 29 }
EntityCollisionClass = { ENTCOLL_NONE = 0 }
GridCollisionClass = { COLLISION_NONE = 0 }
SoundEffect = { SOUND_ANGEL_BEAM = 276 }

local soundCalls = {}
SFXManager = function()
    return {
        Play = function(_, id, volume, frameDelay, loop, pitch, pan)
            soundCalls[#soundCalls + 1] = {
                id = id,
                volume = volume,
                frameDelay = frameDelay,
                loop = loop,
                pitch = pitch,
                pan = pan,
            }
        end,
    }
end

local eidCalls = {}
EID = {
    addCollectible = function(_, id, description, itemName, language)
        eidCalls[#eidCalls + 1] = {
            id = id,
            description = description,
            itemName = itemName,
            language = language,
        }
    end,
}

Sprite = function()
    local sprite = { Scale = vector(1, 1) }
    function sprite:Load(filename) self.filename = filename end
    function sprite:Play(animation)
        self.animation = animation
        self.playCalls = (self.playCalls or 0) + 1
    end
    function sprite:GetFilename() return self.filename end
    function sprite:GetAnimation() return self.animation end
    function sprite:Update() self.updateCalls = (self.updateCalls or 0) + 1 end
    function sprite:Render(position)
        self.renderCalls = (self.renderCalls or 0) + 1
        self.lastRenderPosition = position
        self.renderHistory = self.renderHistory or {}
        self.renderHistory[#self.renderHistory + 1] = {
            position = position,
            scale = vector(self.Scale.X, self.Scale.Y),
            rotation = self.Rotation,
            color = self.Color,
        }
    end
    return sprite
end

local frame = 0
local roomEntities = {}
local seedCounter = 1000
local function nextSeed()
    seedCounter = seedCounter + 1
    return seedCounter
end

local trinityItemId = 1001

local function makePlayer()
    local p = {
        Type = EntityType.ENTITY_PLAYER,
        InitSeed = nextSeed(),
        Position = vector(0, 0),
        DepthOffset = 0,
        CanFly = false,
        MaxFireDelay = 10,
        hasItem = true,
        dead = false,
        data = {},
        costumeAdds = 0,
        costumeRemoves = 0,
    }
    function p:GetData() return self.data end
    function p:HasCollectible(id) return self.hasItem and id == trinityItemId end
    function p:ToPlayer() return self end
    function p:ToFamiliar() return nil end
    function p:IsDead() return self.dead end
    function p:Exists() return not self.removed end
    function p:AddCostume() self.costumeAdds = self.costumeAdds + 1 end
    function p:RemoveCostume() self.costumeRemoves = self.costumeRemoves + 1 end
    return p
end

local player = makePlayer()
local playerB = makePlayer()

local function makeTear()
    local data = {}
    local sprite = { Scale = vector(1, 1), PlaybackSpeed = 1 }
    local tear = {
        Type = EntityType.ENTITY_TEAR,
        Variant = 0,
        InitSeed = nextSeed(),
        Position = vector(50, 50),
        Velocity = vector(10, 0),
        SpriteOffset = vector(0, 0),
        Height = -20,
        DepthOffset = 5,
        FrameCount = 0,
        data = data,
        sprite = sprite,
        flags = 0,
    }
    function tear:GetData() return self.data end
    function tear:GetSprite() return self.sprite end
    function tear:SetColor(color, duration)
        self.colored = true
        self.colorCalls = (self.colorCalls or 0) + 1
        self.lastColor = color
        self.colorDuration = duration
    end
    function tear:AddTearFlags(flags) self.flags = self.flags | flags end
    function tear:HasTearFlags(flags) return (self.flags & flags) ~= 0 end
    function tear:Exists() return not self.removed end
    function tear:Remove() self.removed = true end
    return tear
end

local function makeLaser(parent, options)
    options = options or {}
    local data = {}
    local laser = {
        Type = EntityType.ENTITY_LASER,
        Variant = 0,
        InitSeed = nextSeed(),
        Parent = parent,
        SpawnerEntity = options.spawner or parent,
        Position = options.position or vector(20, 20),
        ParentOffset = options.parentOffset or vector(0, -12),
        PositionOffset = options.positionOffset or vector(0, -36),
        AngleDegrees = options.angleDegrees or 0,
        DepthOffset = 4,
        FrameCount = options.frameCount or 0,
        data = data,
        colored = false,
        flags = options.flags or 0,
        sample = options.sample or false,
        samples = options.samples,
        OneHit = options.oneHit or false,
    }
    function laser:GetData() return self.data end
    function laser:SetColor(color, duration)
        self.colored = true
        self.lastColor = color
        self.colorDuration = duration
    end
    function laser:IsSampleLaser() return self.sample end
    function laser:IsCircleLaser() return options.circle or false end
    function laser:GetSamples()
        if not self.samples then return nil end
        return setmetatable({
            Get = function(_, index) return self.samples[index + 1] end,
        }, {
            __len = function() return #self.samples end,
        })
    end
    function laser:AddTearFlags(flags) self.flags = self.flags | flags end
    function laser:ClearTearFlags(flags) self.flags = self.flags & (~flags) end
    function laser:HasTearFlags(flags) return (self.flags & flags) ~= 0 end
    function laser:ToPlayer() return nil end
    function laser:ToFamiliar() return nil end
    function laser:Exists() return not self.removed end
    return laser
end

local function makeKnife()
    local data = {}
    local knife = {
        Type = EntityType.ENTITY_KNIFE,
        Variant = 0,
        InitSeed = nextSeed(),
        flying = false,
        knifeVelocity = 0,
        knifeDistance = 0,
        data = data,
        colored = false,
    }
    function knife:GetData() return self.data end
    function knife:SetColor() self.colored = true end
    function knife:IsFlying() return self.flying end
    function knife:GetKnifeVelocity() return self.knifeVelocity end
    function knife:GetKnifeDistance() return self.knifeDistance end
    function knife:ToPlayer() return nil end
    function knife:ToFamiliar() return nil end
    function knife:Exists() return not self.removed end
    return knife
end

local function makeEnemy(isBoss)
    local entity = {
        Type = 10,
        Variant = 0,
        InitSeed = nextSeed(),
        Position = vector(100, 100),
        Size = 20,
        SpriteScale = vector(1, 1),
        SpriteOffset = vector(0, 0),
        DepthOffset = 5,
        dead = false,
        boss = isBoss or false,
        flags = 0,
        data = {},
        damageTaken = 0,
        lastDamageSource = nil,
        HitPoints = 100,
    }
    function entity:IsEnemy() return true end
    function entity:IsDead() return self.dead end
    function entity:Exists() return not self.removed end
    function entity:IsBoss() return self.boss end
    function entity:IsVulnerableEnemy() return true end
    function entity:GetData() return self.data end
    function entity:HasEntityFlags(flags) return (self.flags & flags) ~= 0 end
    function entity:TakeDamage(amount, damageFlags, source, countdown)
        self.damageTaken = self.damageTaken + amount
        self.lastDamageSource = source and source.Entity or nil
        if amount >= self.HitPoints then
            self.dead = true
        end
        return true
    end
    function entity:Remove() self.removed = true; self.dead = true end
    return entity
end

local configOverrides = {}
local damageCalls = {}
local manager = {
    Util = {
        log = function() end,
        warn = function(message) error(message) end,
        angleToVector = function(angle, length)
            local radians = math.rad(angle)
            return vector(math.cos(radians) * length, math.sin(radians) * length)
        end,
    },
}
function manager:getConfig(module, key, fallback)
    if configOverrides[key] ~= nil then return configOverrides[key] end
    local value = module.config[key]
    if value == nil then return fallback end
    return value
end
function manager:findPlayerWithCollectible() return player.hasItem and player or nil end
function manager:anyPlayerHasCollectible() return player.hasItem end
function manager:dealDamage(target, amount, damageFlags, source, channel)
    damageCalls[#damageCalls + 1] = { target = target, channel = channel }
    return target:TakeDamage(amount, damageFlags or 0, source or EntityRef(target), 1)
end

local customVisualVariant = 600
local revelationConfig = { ID = CollectibleType.COLLECTIBLE_REVELATION }
Isaac = {
    GetItemIdByName = function(name) return name == "Trinity" and trinityItemId or -1 end,
    GetEntityVariantByName = function(name)
        if name == "Penitent Relics Trinity Visual" then return customVisualVariant end
        return -1
    end,
    GetItemConfig = function()
        return {
            GetCollectible = function(_, id)
                if id == CollectibleType.COLLECTIBLE_REVELATION then
                    return revelationConfig
                end
                return nil
            end,
        }
    end,
    GetPlayer = function(i) return (i == 0) and player or nil end,
    GetRoomEntities = function() return roomEntities end,
    WorldToScreen = function(position) return position end,
    DebugString = function() end,
    Spawn = function(entityType, variant, _, position)
        local sprite = Sprite()
        local effect = {
            Type = entityType,
            Variant = variant,
            Position = position,
            Velocity = Vector.Zero,
            SpriteOffset = vector(0, 0),
            SpriteScale = vector(1, 1),
            DepthOffset = 0,
            data = {},
            sprite = sprite,
            dead = false,
            removed = false,
        }
        function effect:GetData() return self.data end
        function effect:GetSprite() return self.sprite end
        function effect:ToEffect() return self end
        function effect:SetColor() self.colored = true end
        function effect:SetTimeout(n) self.timeout = n end
        function effect:IsDead() return self.dead end
        function effect:Exists() return not self.removed end
        function effect:IsEnemy() return false end
        function effect:Remove() self.removed = true; self.dead = true end
        table.insert(roomEntities, effect)
        return effect
    end,
}

Game = function()
    return {
        GetFrameCount = function() return frame end,
        GetNumPlayers = function() return 1 end,
    }
end

local trinity = dofile("mod/modules/trinity/init.lua")
trinity.manager = manager
trinity:onRegister(manager)

-- EID: the detailed mechanic description is registered once at load with the
-- correct id, name and language, and the short pickup prompt stays thematic.
assert(#eidCalls == 1, "EID description was not registered at load")
assert(eidCalls[1].id == trinityItemId
        and eidCalls[1].itemName == "Trinity"
        and eidCalls[1].language == "en_us",
    "EID registration arguments are wrong")
assert(eidCalls[1].description:find("Judgment", 1, true)
        and eidCalls[1].description:find("1.5x", 1, true)
        and eidCalls[1].description:find("5x damage", 1, true)
        and eidCalls[1].description:find("pierces", 1, true)
        and eidCalls[1].description:find("homes", 1, true)
        and eidCalls[1].description:find("Father's Mark", 1, true)
        and eidCalls[1].description:find("Son's Mark", 1, true),
    "EID description does not cover every effect concisely")

local function fireWith(playerRef, ctxExtra)
    local tear = makeTear()
    trinity:onFireTear(tear, { player = playerRef })
    return tear
end

-- ---------------------------------------------------------------------------
-- Stats cache: flight and tears bonus only while holding the item
-- ---------------------------------------------------------------------------
player.hasItem = true
player.CanFly = false
player.MaxFireDelay = 10
trinity:onEvaluateCache(player, CacheFlag.CACHE_FLYING)
assert(player.CanFly == true, "CACHE_FLYING did not grant flight")
trinity:onEvaluateCache(player, CacheFlag.CACHE_FIREDELAY)
local expectedDelay = 30 / (30 / (10 + 1) + 0.7) - 1
assert(math.abs(player.MaxFireDelay - expectedDelay) < 0.001,
    "CACHE_FIREDELAY did not convert the tears bonus")
player.hasItem = false
player.CanFly = false
trinity:onEvaluateCache(player, CacheFlag.CACHE_FLYING)
assert(player.CanFly == false, "flight stayed on without the item")
trinity:onEvaluateCache(player, CacheFlag.CACHE_FIREDELAY)
assert(math.abs(player.MaxFireDelay - expectedDelay) < 0.001,
    "fire delay changed without the item")
player.hasItem = true

-- ---------------------------------------------------------------------------
-- Tier rotation: 6 shots cycle Father -> Son -> Spirit
-- ---------------------------------------------------------------------------
player.data.pr_trinity_counter = nil
local expectedTiers = { 0, 1, 2, 0, 1, 2 }
for i = 1, 6 do
    local tear = fireWith(player)
    assert(tear.data.pr_trinity_tier == expectedTiers[i],
        "shot " .. i .. " did not receive tier " .. expectedTiers[i])
    assert(tear.colored, "assigned tear was not tinted")
end
assert(player.data.pr_trinity_counter == 0,
    "counter did not wrap after six shots")

-- ---------------------------------------------------------------------------
-- Assignment idempotency: Fire + first-frame Update fallback advance once
-- ---------------------------------------------------------------------------
player.data.pr_trinity_counter = 0
local tear = makeTear()
tear.FrameCount = 1
trinity:onFireTear(tear, { player = player })
assert(player.data.pr_trinity_counter == 1, "fire did not advance the counter")
trinity:onTearUpdate(tear, { player = player })
assert(player.data.pr_trinity_counter == 1,
    "update fallback advanced the counter twice")
assert(tear.data.pr_trinity_tier == 0, "update fallback changed the tier")

-- Fallback-only assignment: a tear that skipped onFireTear still gets a tier
player.data.pr_trinity_counter = 0
roomEntities = {}
local lateTear = makeTear()
lateTear.FrameCount = 1
trinity:onTearUpdate(lateTear, { player = player })
assert(lateTear.data.pr_trinity_tier == 0, "update fallback did not assign")
assert(player.data.pr_trinity_counter == 1, "fallback advanced the counter once")
assert(lateTear.sprite.Scale.X > 1.14, "father fallback tear was not scaled")
trinity:onTearUpdate(lateTear, { player = player })
assert(player.data.pr_trinity_counter == 1,
    "repeated updates advanced the counter twice")

-- ---------------------------------------------------------------------------
-- Aspect tear properties: Son pierces, Spirit homes
-- ---------------------------------------------------------------------------
player.data.pr_trinity_counter = 1
local sonTear = makeTear()
trinity:onFireTear(sonTear, { player = player })
assert(sonTear:HasTearFlags(TearFlags.TEAR_PIERCING), "son tear is not piercing")
player.data.pr_trinity_counter = 2
local spiritTear = makeTear()
trinity:onFireTear(spiritTear, { player = player })
assert(spiritTear:HasTearFlags(TearFlags.TEAR_HOMING), "spirit tear is not homing")

-- ---------------------------------------------------------------------------
-- No item: tears get no tier and hits apply nothing
-- ---------------------------------------------------------------------------
player.hasItem = false
player.data.pr_trinity_counter = 0
local plainTear = makeTear()
trinity:onFireTear(plainTear, { player = player })
assert(plainTear.data.pr_trinity_tier == nil, "tear got a tier without the item")
local target = makeEnemy(false)
roomEntities = { target }
trinity:onAttackHit(target, 3.5, 0, {}, 0,
    { player = player, type = "tear", entity = plainTear })
assert(target.data.pr_trinity_father_mark == nil, "hit applied a mark without the item")
assert(target.damageTaken == 0, "hit dealt damage without the item")
player.hasItem = true

-- ---------------------------------------------------------------------------
-- Father mark
-- ---------------------------------------------------------------------------
frame = 100
player.data.pr_trinity_counter = 0
roomEntities = {}
target = makeEnemy(false)
roomEntities = { target }
local fatherTear = fireWith(player)
trinity:onAttackHit(target, 3.5, 0, {}, 0,
    { player = player, type = "tear", entity = fatherTear })
assert(target.data.pr_trinity_father_mark == 250,
    "father mark expiry frame is wrong")
assert(target.damageTaken == 0, "father hit added damage")
local fatherIcon = target.data.pr_trinity_father_icon.Ref
assert(fatherIcon.sprite.filename == "gfx/effects/trinity_mark_father.anm2",
    "father mark did not create its overhead icon")
assert(fatherIcon.Variant == customVisualVariant,
    "father mark reused a native short-lived effect variant")
assert(fatherIcon.timeout == -1,
    "father mark icon must remain until explicit cleanup")

-- ---------------------------------------------------------------------------
-- Son: 1.5x unmarked, 3.0x vs Father-marked targets; son mark only on marked
-- ---------------------------------------------------------------------------
frame = 110
player.data.pr_trinity_counter = 1
roomEntities = { target }
local sonTear = makeTear()
trinity:onFireTear(sonTear, { player = player })
trinity:onAttackHit(target, 3.5, 0, {}, 0,
    { player = player, type = "tear", entity = sonTear })
assert(math.abs(target.damageTaken - 7.0) < 0.001,
    "marked son hit did not deal 2.0x delta (3.0x total)")
assert(target.data.pr_trinity_son_mark == 260,
    "son mark expiry frame is wrong")
assert(target.lastDamageSource == player,
    "incidental damage was not sourced from the player")
local sonIcon = target.data.pr_trinity_son_icon.Ref
assert(sonIcon.sprite.filename == "gfx/effects/trinity_mark_son.anm2",
    "son mark did not create its overhead icon")

local freshTarget = makeEnemy(false)
roomEntities = { freshTarget }
player.data.pr_trinity_counter = 1
local sonTear2 = makeTear()
trinity:onFireTear(sonTear2, { player = player })
trinity:onAttackHit(freshTarget, 3.5, 0, {}, 0,
    { player = player, type = "tear", entity = sonTear2 })
assert(math.abs(freshTarget.damageTaken - 1.75) < 0.001,
    "unmarked son hit did not deal 0.5x delta (1.5x total)")
assert(freshTarget.data.pr_trinity_son_mark == nil,
    "son mark was applied without a father mark")

-- ---------------------------------------------------------------------------
-- Spirit: 2.0x without dual marks, no judgment with only the father mark
-- ---------------------------------------------------------------------------
frame = 300
player.data.pr_trinity_counter = 2
local spiritOnly = makeEnemy(false)
roomEntities = { spiritOnly }
local spiritTear = makeTear()
trinity:onFireTear(spiritTear, { player = player })
trinity:onAttackHit(spiritOnly, 3.5, 0, {}, 0,
    { player = player, type = "tear", entity = spiritTear })
assert(math.abs(spiritOnly.damageTaken - 3.5) < 0.001,
    "spirit hit on an unmarked enemy did not deal 1.0x delta (2.0x total)")
assert(#trinity.judgmentEffects == 0, "judgment fired without dual marks")
assert(#soundCalls == 0, "judgment sound played without dual marks")

frame = 310
player.data.pr_trinity_counter = 0
local fatherOnly = makeEnemy(false)
roomEntities = { fatherOnly }
local t1 = fireWith(player)
trinity:onAttackHit(fatherOnly, 3.5, 0, {}, 0,
    { player = player, type = "tear", entity = t1 })
player.data.pr_trinity_counter = 2
local t2 = makeTear()
trinity:onFireTear(t2, { player = player })
trinity:onAttackHit(fatherOnly, 3.5, 0, {}, 0,
    { player = player, type = "tear", entity = t2 })
assert(math.abs(fatherOnly.damageTaken - 3.5) < 0.001,
    "spirit hit with only the father mark must stay at 2.0x total")
assert(#trinity.judgmentEffects == 0, "judgment fired with only the father mark")
assert(fatherOnly.data.pr_trinity_father_mark ~= nil,
    "non-judgment spirit hit cleared the father mark")

-- ---------------------------------------------------------------------------
-- Judgment: dual marks + Spirit -> burst, marks cleared, visuals tracked
-- ---------------------------------------------------------------------------
frame = 400
player.data.pr_trinity_counter = 0
local judged = makeEnemy(false)
roomEntities = { judged }
local j1 = fireWith(player)
trinity:onAttackHit(judged, 3.5, 0, {}, 0,
    { player = player, type = "tear", entity = j1 })
local judgedFatherIcon = judged.data.pr_trinity_father_icon.Ref
local j2 = fireWith(player)
trinity:onAttackHit(judged, 3.5, 0, {}, 0,
    { player = player, type = "tear", entity = j2 })
local judgedSonIcon = judged.data.pr_trinity_son_icon.Ref
frame = 405
local j3 = fireWith(player)
trinity:onAttackHit(judged, 3.5, 0, {}, 0,
    { player = player, type = "tear", entity = j3 })
-- son delta 7.0 + judgment delta 14.0 = 21.0 (5.0x total on the main target)
assert(math.abs(judged.damageTaken - 21.0) < 0.001,
    "judgment main-target damage is not 5.0x total")
assert(judged.data.pr_trinity_father_mark == nil
        and judged.data.pr_trinity_son_mark == nil,
    "judgment did not clear the target marks")
assert(judgedFatherIcon.removed and judgedSonIcon.removed,
    "judgment did not remove the mark icons")
assert(#trinity.judgmentEffects == 2, "judgment did not spawn pillar and ring")
assert(#soundCalls == 1, "judgment did not play exactly one sound")
assert(soundCalls[1].id == SoundEffect.SOUND_ANGEL_BEAM
        and soundCalls[1].volume == 0.90
        and soundCalls[1].frameDelay == 6
        and soundCalls[1].loop == false
        and soundCalls[1].pitch == 1.00
        and soundCalls[1].pan == 0,
    "judgment sound did not use the configured angel-beam playback")
local pillarEntry = trinity.judgmentEffects[1]
assert(pillarEntry.kind == "pillar"
        and pillarEntry.ptr.Ref.sprite.filename == "gfx/effects/trinity_judgment.anm2",
    "judgment pillar did not load its authored animation")

-- Judgment visuals are cleaned up after judgmentEffectFrames
frame = 410
trinity:onUpdate()
local ringEntry = trinity.judgmentEffects[2]
assert(ringEntry.kind == "ring"
        and ringEntry.ptr.Ref.sprite.filename
            == "gfx/effects/trinity_judgment_ring.anm2",
    "judgment seal did not load its authored animation")
assert(ringEntry.ptr.Ref.sprite.animation == "Idle"
        and pillarEntry.ptr.Ref.sprite.animation == "Idle",
    "judgment authored animations were not started")
frame = 428
trinity:onUpdate()
assert(#trinity.judgmentEffects == 2, "judgment visuals ended too early")
frame = 429
trinity:onUpdate()
assert(#trinity.judgmentEffects == 0, "judgment visuals were not cleaned up")

-- ---------------------------------------------------------------------------
-- Judgment AOE: near enemies take 2.0x, main target no double-dip, far none
-- ---------------------------------------------------------------------------
frame = 500
player.data.pr_trinity_counter = 0
local aoeMain = makeEnemy(false)
aoeMain.Position = vector(500, 500)
local aoeNear = makeEnemy(false)
aoeNear.Position = vector(540, 500)
local aoeFar = makeEnemy(false)
aoeFar.Position = vector(700, 500)
roomEntities = { aoeMain, aoeNear, aoeFar }
local a1 = fireWith(player)
trinity:onAttackHit(aoeMain, 3.5, 0, {}, 0,
    { player = player, type = "tear", entity = a1 })
local a2 = fireWith(player)
trinity:onAttackHit(aoeMain, 3.5, 0, {}, 0,
    { player = player, type = "tear", entity = a2 })
local a3 = fireWith(player)
trinity:onAttackHit(aoeMain, 3.5, 0, {}, 0,
    { player = player, type = "tear", entity = a3 })
assert(math.abs(aoeMain.damageTaken - 21.0) < 0.001,
    "AOE hit the main target twice")
assert(math.abs(aoeNear.damageTaken - 7.0) < 0.001,
    "near enemy did not take the 2.0x AOE splash")
assert(aoeFar.damageTaken == 0, "enemy outside the radius took AOE damage")
assert(aoeNear.data.pr_trinity_father_mark == nil,
    "AOE splash disturbed the near enemy's own marks")
frame = 524
trinity:onUpdate()
assert(#trinity.judgmentEffects == 0,
    "AOE judgment visuals were not cleaned up")
assert(#soundCalls == 2, "a second judgment did not play one additional sound")
configOverrides.judgmentSoundEnabled = false
trinity:playJudgmentSound()
assert(#soundCalls == 2, "disabled judgment sound still played")
configOverrides.judgmentSoundEnabled = nil

-- ---------------------------------------------------------------------------
-- Bomb exclusion: no tier, no mark, no damage, no judgment
-- ---------------------------------------------------------------------------
frame = 600
player.data.pr_trinity_counter = 0
local bomb = {
    Type = EntityType.ENTITY_BOMBDROP,
    Variant = 0,
    InitSeed = nextSeed(),
    data = {},
}
function bomb:GetData() return self.data end
local bombTarget = makeEnemy(false)
roomEntities = { bombTarget }
trinity:onAttackHit(bombTarget, 3.5, 0, {}, 0,
    { player = player, type = "bomb", entity = bomb })
assert(bombTarget.data.pr_trinity_father_mark == nil,
    "bomb hit applied a mark")
assert(bombTarget.damageTaken == 0, "bomb hit dealt Trinity damage")
assert(#trinity.judgmentEffects == 0, "bomb hit triggered judgment")

-- ---------------------------------------------------------------------------
-- Lasers: Update-safe init, same-volley grouping and 8-tick persistent cycle
-- ---------------------------------------------------------------------------
frame = 700
roomEntities = {}
player.data.pr_trinity_counter = 0
player.data.pr_trinity_laser_volley = nil
local mainLaser = makeLaser(player, { oneHit = true })
trinity:onLaserInit(mainLaser, { player = player })
assert(mainLaser.data.pr_trinity_tier == 0,
    "one-hit Technology laser did not receive a tier during Init")
assert(player.data.pr_trinity_counter == 1,
    "Technology laser Init did not advance exactly once")
assert(#trinity.laserMuzzleEffects == 0,
    "laser Init consumed the update-timed muzzle pulse")
local technologyTarget = makeEnemy(false)
roomEntities = { technologyTarget }
trinity:onAttackHit(technologyTarget, 10, DamageFlag.DAMAGE_LASER, {}, 0,
    { player = player, type = "laser", entity = nil })
assert(technologyTarget.data.pr_trinity_father_mark ~= nil,
    "Technology damage before its first Update did not recover the Init tier")
trinity:onLaserUpdate(mainLaser, { player = player })
assert(mainLaser.data.pr_trinity_tier == 0, "main laser did not get a tier")
assert(player.data.pr_trinity_counter == 1,
    "first Technology update advanced its Init-assigned tier twice")
assert(mainLaser.colored, "main laser was not tinted")
assert(#trinity.laserMuzzleEffects == 1,
    "main laser did not create exactly one muzzle pulse")
assert(trinity.laserMuzzleEffects[1].sprite.filename
        == "gfx/effects/trinity_laser_muzzle.anm2"
        and trinity.laserMuzzleEffects[1].sprite.animation == "Pulse",
    "laser muzzle did not start its authored Pulse animation")
assert(trinity.laserMuzzleEffects[1].sprite.Scale.X == 1.10,
    "laser muzzle is too small to read at gameplay scale")

-- Multiple main roots emitted in the same frame share one volley tier and one
-- muzzle, but retain independent root hashes for incidental-damage channels.
local siblingRoot = makeLaser(player)
trinity:onLaserUpdate(siblingRoot, { player = player })
assert(siblingRoot.data.pr_trinity_tier == 0,
    "same-frame sibling root did not share the volley tier")
assert(player.data.pr_trinity_counter == 1,
    "same-frame sibling root advanced the counter")
assert(#trinity.laserMuzzleEffects == 1,
    "same-frame sibling root duplicated the muzzle pulse")
assert(siblingRoot.data.pr_trinity_laser_root_hash
        ~= mainLaser.data.pr_trinity_laser_root_hash,
    "separate main roots share a damage-channel hash")

local childLaser = makeLaser(mainLaser)
trinity:onLaserInit(childLaser, { player = player })
assert(childLaser.data.pr_trinity_tier == 0, "child laser did not inherit")
assert(childLaser.data.pr_trinity_laser_root_hash
        == mainLaser.data.pr_trinity_laser_root_hash,
    "child laser did not inherit its canonical root hash")
assert(player.data.pr_trinity_counter == 1,
    "child laser advanced the counter")

-- Repentance+ can expose a sample segment through SpawnerEntity instead of
-- Parent. It must inherit without suppressing normal sample-backed Brimstone.
local sampleLaser = makeLaser(nil, { sample = true, spawner = mainLaser })
trinity:onLaserInit(sampleLaser, { player = player })
assert(sampleLaser.data.pr_trinity_tier == 0,
    "SpawnerEntity sample laser did not inherit its root tier")
assert(sampleLaser.data.pr_trinity_laser_root_hash
        == mainLaser.data.pr_trinity_laser_root_hash,
    "SpawnerEntity sample laser did not inherit its root hash")
assert(player.data.pr_trinity_counter == 1,
    "SpawnerEntity sample laser advanced the counter")

-- A root sample laser is valid too; IsSampleLaser alone must never suppress
-- normal Brimstone assignment.
frame = 701
local sampleRoot = makeLaser(nil, { sample = true, spawner = player })
trinity:onLaserUpdate(sampleRoot, { player = player })
assert(type(sampleRoot.data.pr_trinity_tier) == "number",
    "sample-backed root Brimstone was skipped")
player.data.pr_trinity_counter = 1

frame = 702
mainLaser.Position = vector(45, 55)
mainLaser.samples = { vector(70, 30), vector(200, 30) }
trinity:updateLaserMuzzleEffects(frame)
trinity:onRender()
assert(trinity.laserMuzzleEffects[1].sprite.updateCalls == 1,
    "laser muzzle sprite did not advance on logical Update")
assert(trinity.laserMuzzleEffects[1].sprite.renderCalls == 2
        and trinity.laserMuzzleEffects[1].sprite.lastRenderPosition.X == 70
        and trinity.laserMuzzleEffects[1].sprite.lastRenderPosition.Y == -6,
    "laser muzzle did not combine the beam sample with its render offset")
local muzzleHistory = trinity.laserMuzzleEffects[1].sprite.renderHistory
assert(muzzleHistory[1].scale.X > muzzleHistory[2].scale.X
        and muzzleHistory[2].scale.X > 1.10,
    "laser muzzle did not render a wider glow around its breathing core")
assert(muzzleHistory[1].rotation < 0,
    "laser muzzle did not apply its subtle authored rotation")

mainLaser.samples = { vector(-500, -500) }
local fallbackPosition = trinity:getLaserMuzzlePosition(mainLaser)
assert(fallbackPosition.X == 45 and fallbackPosition.Y == 7,
    "laser muzzle did not reject an invalid path sample and use its fallback")

local techXLaser = makeLaser(player, {
    circle = true,
    position = vector(160, 120),
    parentOffset = vector(11, -9),
    positionOffset = vector(-18, 27),
})
local techXPosition = trinity:getLaserMuzzlePosition(techXLaser)
assert(techXPosition.X == 160 and techXPosition.Y == 120,
    "Tech X muzzle did not stay centered on the native circular laser")

frame = 703
local techXMuzzle = {
    sprite = Sprite(),
    rootPtr = EntityPtr(techXLaser),
    born = frame,
    frames = 38,
}
techXLaser.data.pr_trinity_tier = 0
trinity.laserMuzzleEffects[#trinity.laserMuzzleEffects + 1] = techXMuzzle
trinity:onRender()
assert(techXMuzzle.sprite.renderCalls == nil,
    "Tech X muzzle was rendered without its laser RenderOffset")
trinity:onLaserRender(techXLaser, vector(13, -7), { player = player })
assert(techXMuzzle.sprite.renderCalls == 2
        and techXMuzzle.sprite.lastRenderPosition.X == 173
        and techXMuzzle.sprite.lastRenderPosition.Y == 113,
    "Tech X muzzle did not use the circular laser's render callback offset")
table.remove(trinity.laserMuzzleEffects, #trinity.laserMuzzleEffects)
techXLaser.removed = true

frame = 707
trinity:onLaserUpdate(mainLaser, { player = player })
assert(mainLaser.data.pr_trinity_tier == 0,
    "laser changed tier before eight logical ticks")
frame = 708
trinity:onLaserUpdate(mainLaser, { player = player })
trinity:onLaserUpdate(childLaser, { player = player })
assert(mainLaser.data.pr_trinity_tier == 1
        and childLaser.data.pr_trinity_tier == 1,
    "root and child did not switch together at tick eight")
assert(player.data.pr_trinity_counter == 2,
    "tick-eight transition did not advance exactly once")

frame = 716
trinity:onLaserUpdate(mainLaser, { player = player })
assert(mainLaser.data.pr_trinity_tier == 2,
    "persistent laser did not reach Spirit at tick sixteen")
assert(mainLaser:HasTearFlags(TearFlags.TEAR_HOMING),
    "Spirit laser did not receive native homing")
player.hasItem = false
trinity:onLaserUpdate(mainLaser, { player = player })
assert(not mainLaser:HasTearFlags(TearFlags.TEAR_HOMING),
    "item removal kept Trinity-owned laser homing")
player.hasItem = true
trinity:onLaserUpdate(mainLaser, { player = player })
assert(mainLaser:HasTearFlags(TearFlags.TEAR_HOMING),
    "Spirit homing was not restored while the item was held")
frame = 724
trinity:onLaserUpdate(mainLaser, { player = player })
assert(mainLaser.data.pr_trinity_tier == 0,
    "persistent laser did not wrap to Father")
assert(not mainLaser:HasTearFlags(TearFlags.TEAR_HOMING),
    "Trinity-owned homing remained after leaving Spirit")

-- Existing native homing is never removed when Trinity rotates away.
frame = 730
player.data.pr_trinity_counter = 2
local nativeHomingLaser = makeLaser(player, { flags = TearFlags.TEAR_HOMING })
trinity:onLaserUpdate(nativeHomingLaser, { player = player })
frame = 738
trinity:onLaserUpdate(nativeHomingLaser, { player = player })
trinity:updateLaserMuzzleEffects(frame)
assert(nativeHomingLaser:HasTearFlags(TearFlags.TEAR_HOMING),
    "tier transition removed pre-existing native homing")
assert(trinity.laserMuzzleEffects[1].born == 738
        and trinity.laserMuzzleEffects[1].sprite.playCalls == 2,
    "persistent laser did not replay its muzzle animation after 38 frames")

-- Root and child damage share one channel; a separate sibling root does not.
damageCalls = {}
local channelTarget = makeEnemy(false)
trinity:dealIncidental(channelTarget, 1, player, mainLaser)
trinity:dealIncidental(channelTarget, 1, player, childLaser)
trinity:dealIncidental(channelTarget, 1, player, siblingRoot)
assert(damageCalls[1].channel == damageCalls[2].channel,
    "child laser used a different incidental-damage channel")
assert(damageCalls[1].channel ~= damageCalls[3].channel,
    "separate main roots collapsed into one incidental-damage channel")

-- Laser hits read the freshly refreshed tier in the damage callback.
frame = 740
player.data.pr_trinity_counter = 0
local hitLaser = makeLaser(player)
local laserTarget = makeEnemy(false)
roomEntities = { laserTarget }
trinity:onAttackHit(laserTarget, 10, 0, {}, 0,
    { player = player, type = "laser", entity = hitLaser })
assert(laserTarget.data.pr_trinity_father_mark ~= nil,
    "laser hit did not apply the current Father behavior")

-- Native Brimstone can report the player as EntityRef.Entity. The framework
-- then supplies a laser context without an entity, and Trinity recovers the
-- active root from the current update instead of dropping the hit.
frame = 741
player.data.pr_trinity_counter = 0
local sourceFallbackLaser = makeLaser(player)
trinity:onLaserUpdate(sourceFallbackLaser, { player = player })
local sourceFallbackTarget = makeEnemy(false)
trinity:onAttackHit(sourceFallbackTarget, 10, DamageFlag.DAMAGE_LASER, {}, 0,
    { player = player, type = "laser", entity = nil })
assert(sourceFallbackTarget.data.pr_trinity_father_mark ~= nil,
    "player-sourced Brimstone damage did not recover the active laser tier")

frame = 751
mainLaser.removed = true
sampleRoot.removed = true
nativeHomingLaser.removed = true
sourceFallbackLaser.removed = true
trinity:updateLaserMuzzleEffects(frame)
assert(#trinity.laserMuzzleEffects == 0,
    "laser muzzle pulse survived beyond its authored lifetime")

-- ---------------------------------------------------------------------------
-- Mom's Knife: every owned knife reads one independent player clock
-- ---------------------------------------------------------------------------
frame = 800
player.data.pr_trinity_counter = 2
player.data.pr_trinity_knife_clock_start = nil
local knife = makeKnife()
trinity:onKnifeUpdate(knife, { player = player })
assert(knife.data.pr_trinity_tier == 0 and knife.colored,
    "held Mom's Knife did not immediately receive the shared Father tier")
assert(player.data.pr_trinity_counter == 2,
    "independent knife clock changed the tear/laser attack counter")

local siblingKnife = makeKnife()
frame = 807
trinity:onKnifeUpdate(knife, { player = player })
trinity:onKnifeUpdate(siblingKnife, { player = player })
assert(knife.data.pr_trinity_tier == 0
        and siblingKnife.data.pr_trinity_tier == 0,
    "all owned knives did not share Father before the eight-frame boundary")

frame = 808
trinity:onKnifeUpdate(knife, { player = player })
trinity:onKnifeUpdate(siblingKnife, { player = player })
assert(knife.data.pr_trinity_tier == 1
        and siblingKnife.data.pr_trinity_tier == 1,
    "all owned knives did not switch to Son together")
assert(player.data.pr_trinity_counter == 2,
    "shared knife phase polluted the normal attack rotation")

-- Unmarked Son keeps the standard 1.5x Trinity multiplier.
local unmarkedKnifeTarget = makeEnemy(false)
roomEntities = { unmarkedKnifeTarget }
trinity:onAttackHit(unmarkedKnifeTarget, 10, 0, {}, 0,
    { player = player, type = "knife", entity = knife })
assert(math.abs(unmarkedKnifeTarget.damageTaken - 5.0) < 0.001,
    "unmarked Son knife did not keep the standard 1.5x multiplier")

frame = 816
trinity:onKnifeUpdate(knife, { player = player })
trinity:onKnifeUpdate(siblingKnife, { player = player })
assert(knife.data.pr_trinity_tier == 2,
    "shared knife clock did not switch to Spirit")
assert(siblingKnife.data.pr_trinity_tier == 2,
    "a sibling knife fell out of the shared Spirit phase")

-- Unmarked Spirit keeps the standard 2.0x Trinity multiplier.
local unmarkedSpiritKnifeTarget = makeEnemy(false)
roomEntities = { unmarkedSpiritKnifeTarget }
trinity:onAttackHit(unmarkedSpiritKnifeTarget, 10, 0, {}, 0,
    { player = player, type = "knife", entity = knife })
assert(math.abs(unmarkedSpiritKnifeTarget.damageTaken - 10.0) < 0.001,
    "unmarked Spirit knife did not keep the standard 2.0x multiplier")

-- Marked knife hits retain the standard 3x Son and 5x Judgment branches.
local knifeTarget = makeEnemy(false)
roomEntities = { knifeTarget }
frame = 824
trinity:onKnifeUpdate(knife, { player = player })
trinity:onAttackHit(knifeTarget, 10, 0, {}, 0,
    { player = player, type = "knife", entity = knife })
frame = 832
trinity:onKnifeUpdate(knife, { player = player })
trinity:onAttackHit(knifeTarget, 10, 0, {}, 0,
    { player = player, type = "knife", entity = knife })
assert(knifeTarget.data.pr_trinity_father_mark ~= nil
        and knifeTarget.data.pr_trinity_son_mark ~= nil,
    "marked Son knife did not preserve both Trinity marks")
assert(math.abs(knifeTarget.damageTaken - 20.0) < 0.001,
    "marked Son knife did not keep the standard 3.0x multiplier")
frame = 840
trinity:onKnifeUpdate(knife, { player = player })
trinity:onAttackHit(knifeTarget, 10, 0, {}, 0,
    { player = player, type = "knife", entity = knife })
assert(math.abs(knifeTarget.damageTaken - 60.0) < 0.001,
    "dual-mark Spirit knife did not keep the standard 5.0x Judgment multiplier")
assert(knifeTarget.data.pr_trinity_father_mark == nil
        and knifeTarget.data.pr_trinity_son_mark == nil,
    "knife Judgment did not clear both marks")

-- Brimstone knives created at different times still read one player phase.
frame = 850
player.data.pr_trinity_knife_clock_start = 850
local barrageA = makeKnife()
local barrageB = makeKnife()
trinity:onKnifeUpdate(barrageA, { player = player })
frame = 858
trinity:onKnifeUpdate(barrageB, { player = player })
trinity:onKnifeUpdate(barrageA, { player = player })
assert(barrageA.data.pr_trinity_tier == 1
        and barrageB.data.pr_trinity_tier == 1,
    "Brimstone knives did not read the same player-level Son phase")
assert(player.data.pr_trinity_counter == 2,
    "Brimstone knives changed the independent tear/laser counter")

-- ---------------------------------------------------------------------------
-- Multi-player: counters are per player
-- ---------------------------------------------------------------------------
player.data.pr_trinity_counter = 0
playerB.data.pr_trinity_counter = 0
local multiA = fireWith(player)
local multiB = fireWith(playerB)
assert(multiA.data.pr_trinity_tier == 0 and multiB.data.pr_trinity_tier == 0,
    "two players did not each start at Father")
assert(player.data.pr_trinity_counter == 1
        and playerB.data.pr_trinity_counter == 1,
    "one player's counter leaked into the other")

-- ---------------------------------------------------------------------------
-- Marks: expiry, death cleanup, per-enemy independence, boss parity
-- ---------------------------------------------------------------------------
frame = 900
player.data.pr_trinity_counter = 0
local markedA = makeEnemy(false)
local markedB = makeEnemy(false)
roomEntities = { markedA, markedB }
local m1 = fireWith(player)
trinity:onAttackHit(markedA, 3.5, 0, {}, 0,
    { player = player, type = "tear", entity = m1 })
assert(markedB.data.pr_trinity_father_mark == nil,
    "marks leaked onto a second enemy")
assert(markedA.data.pr_trinity_father_mark == 1050,
    "expiry frame did not use the logical clock")
local markIcon = markedA.data.pr_trinity_father_icon.Ref

frame = 1049
trinity:onUpdate()
assert(trinity:hasFatherMark(markedA, frame), "mark expired one frame early")
frame = 1050
trinity:onUpdate()
assert(markedA.data.pr_trinity_father_mark == nil,
    "expired mark was not cleared")
assert(markIcon.removed, "expired mark icon was not removed")

-- Bosses take marks exactly like normal enemies
frame = 1100
player.data.pr_trinity_counter = 0
local boss = makeEnemy(true)
roomEntities = { boss }
local b1 = fireWith(player)
trinity:onAttackHit(boss, 5, 0, {}, 0,
    { player = player, type = "tear", entity = b1 })
assert(boss.data.pr_trinity_father_mark == 1250,
    "boss did not receive the father mark")

-- Death cleanup removes marks and icons
frame = 1200
player.data.pr_trinity_counter = 0
local dying = makeEnemy(false)
roomEntities = { dying }
local d1 = fireWith(player)
trinity:onAttackHit(dying, 3.5, 0, {}, 0,
    { player = player, type = "tear", entity = d1 })
local dyingIcon = dying.data.pr_trinity_father_icon.Ref
dying.dead = true
trinity:onUpdate()
assert(dying.data.pr_trinity_father_mark == nil,
    "dead enemy kept its mark")
assert(dyingIcon.removed, "dead enemy kept its mark icon")

-- Room change clears marks and restarts the rotation
player.data.pr_trinity_counter = 2
frame = 1300
player.data.pr_trinity_counter = 0
local roomTarget = makeEnemy(false)
roomEntities = { roomTarget }
local r1 = fireWith(player)
trinity:onAttackHit(roomTarget, 3.5, 0, {}, 0,
    { player = player, type = "tear", entity = r1 })
local roomIcon = roomTarget.data.pr_trinity_father_icon.Ref
player.data.pr_trinity_counter = 2
trinity:onNewRoom()
assert(roomTarget.data.pr_trinity_father_mark == nil,
    "room change did not clear marks")
assert(roomIcon.removed, "room change did not remove icons")
assert(player.data.pr_trinity_counter == 0,
    "room change did not restart the rotation")

-- ---------------------------------------------------------------------------
-- Orbiting orbs: created per holder, cleaned up on game start
-- ---------------------------------------------------------------------------
frame = 1400
roomEntities = {}
player.data.pr_trinity_counter = 0
trinity:onUpdate()
local orbs = player.data.pr_trinity_orbs
assert(orbs and #orbs == 3, "holder did not get three orbs")
assert(orbs[1].Ref.sprite.filename == "gfx/effects/trinity_orb.anm2",
    "orb did not load the custom sprite")
assert(orbs[1].Ref.Variant == customVisualVariant,
    "orb reused a native short-lived effect variant")
assert(orbs[1].Ref.timeout == -1,
    "orb must remain until explicit cleanup")
assert(orbs[1].Ref.sprite.PlaybackSpeed == 0.90
        and orbs[2].Ref.sprite.PlaybackSpeed == 1.00
        and orbs[3].Ref.sprite.PlaybackSpeed == 1.10,
    "orb breathing animations did not receive staggered playback rates")
assert(player.costumeAdds == 1 and player.data.pr_trinity_wings_applied,
    "holder did not receive the original wing costume")
assert(orbs[1].Ref.Position.X ~= orbs[2].Ref.Position.X
        or orbs[1].Ref.Position.Y ~= orbs[2].Ref.Position.Y,
    "orbs overlap at the same position")
trinity:onGameStart(false)
assert(orbs[1].Ref.removed and orbs[2].Ref.removed and orbs[3].Ref.removed,
    "game start did not remove the orbs")
assert(player.costumeRemoves == 1 and not player.data.pr_trinity_wings_applied,
    "game start did not remove Trinity's wing costume")

-- ---------------------------------------------------------------------------
-- Original tear sprite: enriched by color only, with no spawned visual entity
-- ---------------------------------------------------------------------------
frame = 1500
player.data.pr_trinity_counter = 0
roomEntities = {}
local coloredTear = fireWith(player)
assert(#roomEntities == 0, "Trinity spawned a visual entity for an original tear")
local initialColorCalls = coloredTear.colorCalls
coloredTear.FrameCount = 3
trinity:onTearUpdate(coloredTear, { player = player })
assert(coloredTear.colorCalls == initialColorCalls + 1
        and coloredTear.colorDuration == 4,
    "original tear did not receive a smoothly blended pulse color")
coloredTear.FrameCount = 4
trinity:onTearUpdate(coloredTear, { player = player })
assert(coloredTear.colorCalls == initialColorCalls + 1,
    "tear color pulse updated more often than configured")
assert(#roomEntities == 0, "tear color updates spawned residual entities")

-- ---------------------------------------------------------------------------
-- Item removal: persistent visuals, marks and wing costume are cleaned up
-- ---------------------------------------------------------------------------
roomEntities = {}
trinity:onUpdate()
local removedOrbs = player.data.pr_trinity_orbs
local removalTarget = makeEnemy(false)
roomEntities[#roomEntities + 1] = removalTarget
trinity:applyFatherMark(removalTarget, frame)
local removalIcon = removalTarget.data.pr_trinity_father_icon.Ref
player.hasItem = false
frame = 1600
trinity:onUpdate()
assert(player.data.pr_trinity_orbs == nil,
    "item removal kept the orbitals")
assert(removedOrbs[1].Ref.removed and removedOrbs[2].Ref.removed
        and removedOrbs[3].Ref.removed,
    "item removal did not remove the orbital entities")
assert(removalTarget.data.pr_trinity_father_mark == nil and removalIcon.removed,
    "item removal kept an enemy mark or icon")
assert(player.costumeRemoves == 2 and not player.data.pr_trinity_wings_applied,
    "item removal did not remove Trinity's wing costume")
assert(player.data.pr_trinity_knife_clock_start == nil,
    "item removal did not reset the shared Mom's Knife clock")
player.hasItem = true

-- ---------------------------------------------------------------------------
-- Framework regression: channeled dealDamage keeps modules independent while
-- the same attack on the same target stays locked
-- ---------------------------------------------------------------------------
local Manager = dofile("mod/framework/manager.lua")
Manager.Util = {
    safeCall = function(fn)
        fn()
        return true
    end,
}
frame = 2000
Manager._lockFrame = -1
Manager._locks = {}
local victim = makeEnemy(false)
local trinityChannel = "trinity:" .. GetPtrHash(victim)
local saltChannel = "crude_salt:" .. GetPtrHash(victim)
assert(Manager:dealDamage(victim, 1, 0, EntityRef(player), trinityChannel),
    "first channeled call was blocked")
assert(Manager:dealDamage(victim, 2, 0, EntityRef(player), saltChannel),
    "a different module channel was blocked by Trinity's lock")
assert(not Manager:dealDamage(victim, 3, 0, EntityRef(player), trinityChannel),
    "the same channel did not stay locked for the frame")
assert(Manager:dealDamage(victim, 4, 0, EntityRef(player)),
    "a nil channel was blocked by a channeled lock")
assert(not Manager:dealDamage(victim, 5, 0, EntityRef(player)),
    "the legacy nil-channel lock did not stay locked")
frame = 2001
assert(Manager:dealDamage(victim, 6, 0, EntityRef(player), trinityChannel),
    "channeled lock did not reset on the next frame")

-- Framework regression: player-sourced damage never re-enters attack dispatch
local Context = dofile("mod/framework/context.lua")
local contextLaser = makeLaser(nil, { sample = true, spawner = player })
local laserContext = Context.buildLaserContext(contextLaser)
assert(laserContext.isPlayerOwned and laserContext.player == player,
    "sample-backed Brimstone did not resolve its player through SpawnerEntity")
local playerLaserDamage = Context.buildDamageContext({
    Type = EntityType.ENTITY_PLAYER,
    Entity = player,
    SpawnerType = EntityType.ENTITY_PLAYER,
    Variant = 0,
}, DamageFlag.DAMAGE_LASER)
assert(playerLaserDamage and playerLaserDamage.type == "laser"
        and playerLaserDamage.player == player
        and playerLaserDamage.entity == nil,
    "DAMAGE_LASER did not preserve player ownership for active-laser recovery")
assert(Context.buildDamageContext({
    Type = EntityType.ENTITY_PLAYER,
    Variant = 0,
    Entity = nil,
    SpawnerType = EntityType.ENTITY_PLAYER,
}) == nil, "player-sourced incidental damage must not re-enter onAttackHit")

-- Native knife contact can report the player as EntityRef.Entity. The
-- same-frame pre-collision hint restores the real knife exactly once.
frame = 2010
local collisionKnife = makeKnife()
collisionKnife.Parent = player
local collisionTarget = makeEnemy(false)
Context.rememberKnifeCollision(collisionKnife, collisionTarget)
local rawKnifeDamage = Context.buildDamageContext({
    Type = EntityType.ENTITY_KNIFE,
    Entity = player,
    SpawnerType = EntityType.ENTITY_PLAYER,
    Variant = 0,
}, 0)
assert(rawKnifeDamage and rawKnifeDamage.type == "knife"
        and rawKnifeDamage.entity == nil,
    "player-reported knife damage retained a false weapon entity")
local recoveredKnifeDamage = Context.recoverKnifeDamageContext(
    collisionTarget,
    rawKnifeDamage.source or {
        Type = EntityType.ENTITY_KNIFE,
        Entity = player,
        SpawnerType = EntityType.ENTITY_PLAYER,
        Variant = 0,
    },
    rawKnifeDamage
)
assert(recoveredKnifeDamage and recoveredKnifeDamage.entity == collisionKnife
        and recoveredKnifeDamage.player == player,
    "knife collision hint did not recover the real weapon and owner")
local recursiveKnifeDamage = Context.recoverKnifeDamageContext(collisionTarget, {
    Type = EntityType.ENTITY_PLAYER,
    Entity = player,
    SpawnerType = EntityType.ENTITY_PLAYER,
    Variant = 0,
}, nil)
assert(recursiveKnifeDamage == nil,
    "consumed knife collision hint allowed supplemental damage to recurse")

-- Framework regression: onEvaluateCache dispatches with (player, cacheFlag)
Manager.hookTargets = Manager.hookTargets or {}
local cacheCalls = {}
Manager.hookTargets.onEvaluateCache = {
    {
        id = "cache_test",
        onEvaluateCache = function(_, p, flag)
            cacheCalls[#cacheCalls + 1] = { p, flag }
        end,
    },
}
Manager:dispatch("onEvaluateCache", player, CacheFlag.CACHE_FLYING)
assert(cacheCalls[1] and cacheCalls[1][1] == player
        and cacheCalls[1][2] == CacheFlag.CACHE_FLYING,
    "onEvaluateCache dispatch arguments are wrong")

print("Trinity regression tests passed.")
