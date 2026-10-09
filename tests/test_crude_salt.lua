-- Lightweight regression test for the Crude Salt state machine.
-- Run from the repository root with: tools\lua\lua53.exe tests\test_crude_salt.lua

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
    ENTITY_FROZEN_ENEMY = 963,
    ENTITY_EFFECT = 1000,
}
EffectVariant = { EFFECT_NULL = 0, POOF01 = 15 }
SoundEffect = { SOUND_ROCK_CRUMBLE = 138 }
DamageFlag = { DAMAGE_IGNORE_ARMOR = 1 << 1 }
EntityFlag = {
    FLAG_NO_TARGET = 1 << 4,
    FLAG_FREEZE = 1 << 5,
    FLAG_NO_KNOCKBACK = 1 << 26,
    FLAG_FRIENDLY = 1 << 29,
    FLAG_NO_PHYSICS_KNOCKBACK = 1 << 30,
    FLAG_BLEED_OUT = 1 << 34,
    FLAG_ICE = 1 << 50,
}
EntityCollisionClass = { ENTCOLL_NONE = 0, ENTCOLL_PLAYERONLY = 1 }
GridCollisionClass = { COLLISION_NONE = 0 }

Sprite = function()
    local sprite = {}
    function sprite:Load(filename) self.filename = filename end
    function sprite:Play(animation)
        self.animation = animation
        self.frame = 0
        self.playCalls = (self.playCalls or 0) + 1
    end
    function sprite:SetFrame(animation, spriteFrame)
        self.animation = animation
        self.frame = spriteFrame
    end
    function sprite:Stop() self.stopped = true end
    function sprite:IsFinished(animation)
        return self.finishedAnimation == animation
    end
    function sprite:Render(position)
        self.rendered = true
        self.renderPosition = position
    end
    return sprite
end

local frame = 0
local roomEntities = {}
local player = {
    Damage = 3.5,
    Luck = 0,
    Type = EntityType.ENTITY_PLAYER,
    InitSeed = 1,
    Position = vector(0, 0),
    Size = 10,
    hasCrudeSalt = true,
    attackRoll = 1,
}
function player:HasCollectible(id) return self.hasCrudeSalt and id == 1000 end
function player:GetCollectibleRNG(id)
    assert(id == 1000, "weapon hit requested the wrong collectible RNG")
    return { RandomFloat = function() return self.attackRoll end }
end
function player:ToPlayer() return self end
function player:ToFamiliar() return nil end

Game = function()
    return {
        GetFrameCount = function() return frame end,
        GetNumPlayers = function() return 1 end,
    }
end

Isaac = {
    GetItemIdByName = function(name) return name == "Crude Salt" and 1000 or -1 end,
    GetEntityVariantByName = function(name)
        return name == "Penitent Relics Crude Salt Visual" and 601 or -1
    end,
    GetPlayer = function() return player end,
    GetRoomEntities = function() return roomEntities end,
    WorldToRenderPosition = function(position) return position end,
    WorldToScreen = function(position) return position end,
    DebugString = function() end,
    Spawn = function(entityType, variant, _, position)
        local effectSprite = Sprite()
        local effect = {
            Type = entityType,
            Variant = variant,
            Position = position,
            Velocity = Vector.Zero,
            data = {},
            sprite = effectSprite,
            dead = false,
        }
        function effect:GetData() return self.data end
        function effect:GetSprite() return self.sprite end
        function effect:ToEffect() return self end
        function effect:SetColor() self.colored = true end
        function effect:SetTimeout(value) self.timeout = value end
        function effect:IsDead() return self.dead end
        function effect:Exists() return not self.removed end
        function effect:IsEnemy() return false end
        function effect:HasEntityFlags() return false end
        function effect:Remove() self.removed = true; self.dead = true end
        table.insert(roomEntities, effect)
        return effect
    end,
}
SFXManager = function() return { Play = function() end } end

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

local function enemy(isBoss)
    local entity = {
        Type = 10,
        Variant = 0,
        InitSeed = isBoss and 3 or 2,
        Position = vector(100, 100),
        Velocity = vector(1, 0),
        dead = false,
        boss = isBoss,
        data = {},
        damageTaken = 0,
        HitPoints = 10,
        MaxHitPoints = 10,
        Size = 20,
        SizeMulti = vector(1, 1),
        SpriteScale = vector(1, 1),
        SpriteOffset = vector(0, 0),
        PositionOffset = vector(0, 0),
        SpriteRotation = 0,
        flags = 0,
    }
    function entity:IsEnemy() return true end
    function entity:IsDead() return self.dead end
    function entity:Exists() return not self.removed end
    function entity:IsBoss() return self.boss end
    function entity:GetData() return self.data end
    function entity:SetColor() self.colored = true end
    function entity:GetSprite()
        return {
            GetAnimation = function() return "WalkHori" end,
            GetFrame = function() return 2 end,
            GetFilename = function() return "gfx/test_enemy.anm2" end,
        }
    end
    function entity:AddFreeze(source, duration)
        self.frozen = true
        self.freezeSource = source.Entity
        self.freezeDuration = duration
        self.flags = self.flags | EntityFlag.FLAG_FREEZE
    end
    function entity:AddEntityFlags(flags) self.flags = self.flags | flags end
    function entity:ClearEntityFlags(flags)
        self.flags = self.flags & (~flags)
        self.freezeCleared = (flags & EntityFlag.FLAG_FREEZE) ~= 0
    end
    function entity:HasEntityFlags(flags) return (self.flags & flags) ~= 0 end
    function entity:Die() self.dead = true end
    function entity:KillWithSource(source)
        self.dead = true
        self.killSource = source.Entity
    end
    function entity:Kill() self.dead = true end
    function entity:Remove() self.dead = true; self.removed = true end
    function entity:TakeDamage(amount, damageFlags, source, countdown)
        self.damageTaken = self.damageTaken + amount
        self.lastDamageFlags = damageFlags
        self.lastDamageSource = source and source.Entity or nil
        self.lastDamageCountdown = countdown
        if amount >= self.HitPoints then
            self.dead = true
        end
        return true
    end
    return entity
end

local manager = {
    Util = { log = function() end, warn = function(message) error(message) end },
}
function manager:getConfig(module, key, fallback)
    if key == "soundOn" or key == "particleOn" then return false end
    local value = module.config[key]
    if value == nil then return fallback end
    return value
end
function manager:findPlayerWithCollectible() return player end
function manager:anyPlayerHasCollectible() return true end
function manager:dealDamage(target, amount, damageFlags, source)
    return target:TakeDamage(amount, damageFlags or 0, source or EntityRef(target), 1)
end

local salt = dofile("mod/modules/crude_salt/init.lua")
salt.manager = manager
salt:onRegister(manager)

-- EID: the mechanic description is registered once at load with the correct
-- id, name and language; the native pickup prompt stays thematic.
assert(#eidCalls == 1, "Crude Salt EID description was not registered at load")
assert(eidCalls[1].id == 1000
        and eidCalls[1].itemName == "Crude Salt"
        and eidCalls[1].language == "en_us",
    "EID registration arguments are wrong")
assert(eidCalls[1].description:find("salt statue", 1, true)
        and eidCalls[1].description:find("5x", 1, true)
        and eidCalls[1].description:find("Luck", 1, true),
    "EID description does not cover the Crude Salt effects")

local function playerTear(roll)
    local data = {}
    local sprite = { Scale = vector(1, 1) }
    local tear = {
        Position = vector(50, 50),
        Velocity = vector(10, 0),
        Height = -20,
        SpriteOffset = vector(0, 0),
        DepthOffset = 5,
        FrameCount = 0,
        data = data,
        sprite = sprite,
        roll = roll,
    }
    function tear:GetData() return self.data end
    function tear:GetSprite() return self.sprite end
    function tear:GetDropRNG()
        return { RandomFloat = function() return self.roll end }
    end
    function tear:SetColor(color, duration)
        self.colored = true
        self.colorCalls = (self.colorCalls or 0) + 1
        self.lastColor = color
        self.colorDuration = duration
    end
    return tear
end

assert(math.abs(salt:getTearChance(0) - 0.40) < 0.0001, "0 Luck chance is not 40%")
assert(math.abs(salt:getTearChance(4) - 0.70) < 0.0001, "4 Luck chance is not 70%")
assert(math.abs(salt:getTearChance(8) - 1.00) < 0.0001, "8 Luck chance is not 100%")
assert(math.abs(salt:getTearChance(-5) - 0.40) < 0.0001, "negative Luck went below 40%")

local missedTear = playerTear(0.40)
assert(not salt:rollSaltTear(missedTear, { player = player }),
    "a 40% boundary roll should not become a salt tear")
missedTear.roll = 0
assert(not salt:rollSaltTear(missedTear, { player = player }),
    "the same tear was rolled more than once")

local activeTear = playerTear(0.39)
assert(salt:rollSaltTear(activeTear, { player = player }),
    "a roll below 40% did not become a salt tear")
assert(activeTear.colored and activeTear.sprite.Scale.X > 1.14,
    "salt tear did not receive its special visual")
roomEntities = {}
activeTear.FrameCount = 6
local colorCalls = activeTear.colorCalls
salt:onTearUpdate(activeTear, { player = player })
assert(#roomEntities == 0, "salt tear spawned a residual trail entity")
assert(activeTear.colorCalls == colorCalls + 1 and activeTear.colorDuration == 4,
    "salt tear did not receive its granular color pulse")

player.Luck = 8
local guaranteedTear = playerTear(0.9999)
assert(salt:rollSaltTear(guaranteedTear, { player = player }),
    "8 Luck did not guarantee a salt tear")
player.Luck = 0

local ordinaryTarget = enemy(false)
salt:onAttackHit(ordinaryTarget, 3.5, 0, {}, 0,
    { player = player, type = "tear", entity = missedTear })
assert(ordinaryTarget.data.pr_crude_salt_debuff == nil,
    "an ordinary tear incorrectly applied Crude Salt")

-- Sustained lasers and Mom's Knife roll on every real damage event. There is
-- deliberately no frame interval: successful repeats refresh one debuff and
-- never create a stack. Technology, Tech X and Brimstone all use laser ctx.
local weaponCases = {
    { name = "Technology", type = "laser", entity = nil },
    { name = "Tech X", type = "laser", entity = { Variant = 2 } },
    { name = "Brimstone", type = "laser", entity = { Variant = 1 } },
    { name = "Mom's Knife", type = "knife", entity = { Variant = 0 } },
}
for index, weaponCase in ipairs(weaponCases) do
    local weaponTarget = enemy(false)
    weaponTarget.InitSeed = 20 + index
    roomEntities = { weaponTarget }
    salt:onUpdate()

    player.attackRoll = 0.40
    salt:onAttackHit(weaponTarget, 3.5, 0, {}, 0, {
        player = player,
        type = weaponCase.type,
        entity = weaponCase.entity,
    })
    assert(weaponTarget.data.pr_crude_salt_debuff == nil,
        weaponCase.name .. " applied Crude Salt on the 40% boundary")

    player.attackRoll = 0.39
    salt:onAttackHit(weaponTarget, 3.5, 0, {}, 0, {
        player = player,
        type = weaponCase.type,
        entity = weaponCase.entity,
    })
    local weaponDebuff = weaponTarget.data.pr_crude_salt_debuff
    assert(weaponDebuff ~= nil, weaponCase.name .. " did not apply Crude Salt")

    salt:onAttackHit(weaponTarget, 3.5, 0, {}, 0, {
        player = player,
        type = weaponCase.type,
        entity = weaponCase.entity,
    })
    assert(weaponTarget.data.pr_crude_salt_debuff == weaponDebuff,
        weaponCase.name .. " stacked instead of refreshing its debuff")
end

local unsupportedTarget = enemy(false)
roomEntities = { unsupportedTarget }
salt:onUpdate()
player.attackRoll = 0
salt:onAttackHit(unsupportedTarget, 3.5, 0, {}, 0,
    { player = player, type = "bomb", entity = {} })
assert(unsupportedTarget.data.pr_crude_salt_debuff == nil,
    "an unsupported bomb attack applied Crude Salt")

local unownedTarget = enemy(false)
roomEntities = { unownedTarget }
salt:onUpdate()
player.hasCrudeSalt = false
salt:onAttackHit(unownedTarget, 3.5, 0, {}, 0,
    { player = player, type = "laser", entity = nil })
assert(unownedTarget.data.pr_crude_salt_debuff == nil,
    "a player without Crude Salt applied its laser effect")
player.hasCrudeSalt = true
player.attackRoll = 1
salt:onNewRoom()

local target = enemy(false)
roomEntities = { target }
salt:onUpdate() -- capture +X before the hit
salt:onAttackHit(target, 3.5, 0, {}, 0,
    { player = player, type = "tear", entity = activeTear })

local debuff = target.data.pr_crude_salt_debuff
assert(debuff and debuff.direction.X > 0.99, "hit direction was not stored")
local mark = debuff.markPtr
assert(mark and mark.sprite.filename == "gfx/effects/crude_salt_mark.anm2",
    "salt debuff did not create its custom overhead icon")
assert(mark.active and #salt.saltMarks == 1,
    "salt mark did not use the persistent direct-render record")
assert(mark.sprite.animation == "Idle" and mark.sprite.frame == 1
        and mark.sprite.stopped,
    "salt mark did not begin on its persistent static arrow frame")
local firstDirection = debuff.direction
target.Velocity = vector(0, 1)
frame = 1
salt:onAttackHit(target, 3.5, 0, {}, 0,
    { player = player, type = "tear", entity = activeTear })
assert(target.data.pr_crude_salt_debuff == debuff,
    "later salt tear created a second debuff")
assert(target.data.pr_crude_salt_debuff.direction ~= firstDirection
        and target.data.pr_crude_salt_debuff.direction.Y > 0.99,
    "later salt tear did not update the stored direction")
assert(mark.sprite.playCalls == nil and mark.sprite.animation == "Idle",
    "later salt tear restarted the persistent direction mark")

frame = 1000
target.SpriteOffset = vector(0, -10)
target.PositionOffset = vector(0, -4)
target.SizeMulti = vector(1, 1.5)
salt:onUpdate()
assert(target.data.pr_crude_salt_debuff ~= nil,
    "permanent debuff expired before it was triggered")
assert(mark.sprite.Scale and mark.sprite.Scale.X <= 1.0,
    "salt icon was not scaled to the enemy's size")
assert(mark.position.Y < 45,
    "salt icon was not placed fully above the enemy's visual head")
assert(math.abs(mark.sprite.Rotation - 90) < 0.001,
    "salt direction mark did not point along the stored movement direction")
assert(mark.sprite.animation == "Idle" and mark.sprite.frame == 1
        and mark.sprite.stopped and mark.sprite.playCalls == nil,
    "salt direction mark did not remain on its persistent static frame")
salt:onRender()
assert(mark.sprite.rendered and mark.sprite.renderPosition == mark.position,
    "salt direction mark was not rendered directly from its persistent record")
target.flags = target.flags | EntityFlag.FLAG_BLEED_OUT
frame = 1001
salt:onUpdate()
assert(mark.position.X < target.Position.X,
    "salt icon did not avoid the Backstabber bleed presentation")

target.Velocity = vector(0, -1)
target.Size = 48
target.SpriteScale = vector(1.25, 1.25)
target.SizeMulti = vector(1, 1.2)
target.PositionOffset = vector(3, -5)
frame = 1005
salt:onUpdate()
frame = 1006
salt:onUpdate()
assert(mark.active and mark.sprite.animation == "Idle"
        and mark.sprite.frame == 1 and mark.sprite.stopped,
    "salt direction mark disappeared or animated before the debuff triggered")
frame = 1007
salt:onUpdate()
assert(target.data.pr_crude_salt_debuff == nil, "debuff was not consumed")
assert(target.data.pr_crude_salt_statue_pending,
    "normal enemy was not marked as a pending salt statue")
assert(target.frozen and target.freezeDuration == 60,
    "normal enemy did not receive the native 60-frame freeze")
assert(target:HasEntityFlags(EntityFlag.FLAG_ICE),
    "normal enemy was not marked to become FrozenEnemy on lethal damage")
assert(target.colored and not mark.active,
    "normal enemy did not receive salt color or retained its armed icon")
assert(target.damageTaken == 1000000
        and target.lastDamageFlags == DamageFlag.DAMAGE_IGNORE_ARMOR,
    "normal enemy did not receive one million armor-ignoring damage")
assert(target.killSource == nil and not target.removed,
    "normal enemy used Kill/Remove instead of the native damage system")
local statueRecord = salt.saltStatues[1]
assert(statueRecord and statueRecord.ptr.Ref == target
        and statueRecord.initSeed == target.InitSeed
        and statueRecord.removeAt == 1067
        and math.abs(statueRecord.shatterPresentation.scale - 1.65) < 0.001,
    "native statue was not tracked safely for 60 logical frames")

-- Model the engine replacing the frozen victim with a FrozenEnemy that keeps
-- the original InitSeed. The tracker must adopt and later clean that entity.
target.removed = true
local frozenReplacement = enemy(false)
frozenReplacement.Type = EntityType.ENTITY_FROZEN_ENEMY
frozenReplacement.InitSeed = target.InitSeed
frozenReplacement.flags = frozenReplacement.flags | EntityFlag.FLAG_FREEZE
roomEntities = { frozenReplacement }
frame = 1008
salt:onUpdate()
assert(statueRecord.ptr.Ref == frozenReplacement and frozenReplacement.colored,
    "InitSeed lookup did not adopt and recolor the FrozenEnemy replacement")
frame = 1066
salt:onUpdate()
assert(frozenReplacement:Exists(),
    "native frozen statue was removed before 60 logical frames")
frame = 1067
salt:onUpdate()
assert(not frozenReplacement:Exists() and #salt.saltStatues == 0,
    "native frozen statue was not removed after 60 logical frames")
local disappearShatters = 0
local disappearPoofs = 0
local disappearShatter = nil
for _, spawned in ipairs(roomEntities) do
    if spawned.Type == EntityType.ENTITY_EFFECT and spawned.Variant == 601
        and spawned.sprite.filename == "gfx/effects/crude_salt_shatter.anm2" then
        disappearShatters = disappearShatters + 1
        disappearShatter = spawned
    elseif spawned.Type == EntityType.ENTITY_EFFECT
        and spawned.Variant == EffectVariant.POOF01 then
        disappearPoofs = disappearPoofs + 1
    end
end
assert(disappearShatters == 1 and disappearPoofs == 0,
    "native frozen statue did not replace its smoke poof with one salt shatter")
assert(disappearShatter and math.abs(disappearShatter.SpriteScale.X - 1.65) < 0.001
        and disappearShatter.SpriteOffset.X == 3
        and disappearShatter.SpriteOffset.Y == -15,
    "statue disappearance did not preserve the original enemy's size and offset")

-- Player contact consumes a salt statue before the native frozen-enemy kick
-- can launch it or convert it into an ice tear.
local collisionStatue = enemy(false)
collisionStatue.Type = EntityType.ENTITY_FROZEN_ENEMY
collisionStatue.InitSeed = 77
collisionStatue.flags = collisionStatue.flags | EntityFlag.FLAG_FREEZE
roomEntities = { collisionStatue }
salt.saltStatues = {
    {
        ptr = EntityPtr(collisionStatue),
        initSeed = collisionStatue.InitSeed,
        removeAt = 9999,
        shatterPresentation = { scale = 0.80, offset = vector(2, -6) },
    },
}
local shattersBeforeCollision = #salt.shatterEffects
assert(salt:onPlayerCollide(player, collisionStatue, false) == true,
    "salt-statue collision did not suppress the native frozen-enemy kick")
assert(not collisionStatue:Exists() and #salt.saltStatues == 0,
    "salt-statue collision did not immediately remove the frozen entity")
assert(#salt.shatterEffects == shattersBeforeCollision + 1,
    "salt-statue collision did not create exactly one disappearance animation")
local collisionShatter = salt.shatterEffects[#salt.shatterEffects].ptr.Ref
assert(collisionShatter.SpriteScale.X == 0.80
        and collisionShatter.SpriteOffset.X == 2
        and collisionShatter.SpriteOffset.Y == -6,
    "collision disappearance did not use the preserved monster presentation")
assert(salt:onPlayerCollide(player, enemy(false), false) == nil,
    "ordinary enemy collision was incorrectly overridden")

local boss = enemy(true)
roomEntities = { boss }
frame = 2080
salt:onUpdate()
salt:onAttackHit(boss, 3.5, 0, {}, 0,
    { player = player, type = "tear", entity = activeTear })
local bossMark = boss.data.pr_crude_salt_debuff.markPtr
boss.Velocity = vector(-1, 0)
for current = 2085, 2087 do
    frame = current
    salt:onUpdate()
end
assert(math.abs(boss.damageTaken - 17.5) < 0.001, "boss did not take 5x player damage")
assert(not boss.frozen and #salt.saltStatues == 0,
    "boss incorrectly entered the native salt-statue timer")
assert(boss.data.pr_crude_salt_debuff == nil, "boss retained the consumed debuff")
assert(not bossMark.active, "boss salt icon remained after the debuff triggered")
assert(#salt.shatterEffects == 1,
    "boss trigger did not add its immediate salt shatter visual")
frame = 2088
salt:onUpdate()
assert(math.abs(boss.damageTaken - 17.5) < 0.001, "boss damage repeated without a new debuff")
frame = 2103
salt:onUpdate()
assert(#salt.shatterEffects == 0,
    "salt shatter effects were not explicitly cleaned after 16 logical frames")

local Context = dofile("mod/framework/context.lua")
local tear = {
    Type = EntityType.ENTITY_TEAR,
    Variant = 0,
    InitSeed = 4,
    Parent = player,
    SpawnerEntity = nil,
    SpawnerType = EntityType.ENTITY_PLAYER,
}
function tear:ToPlayer() return nil end
function tear:ToFamiliar() return nil end
local damageContext = Context.buildDamageContext({
    Type = EntityType.ENTITY_TEAR,
    Variant = 0,
    SpawnerType = EntityType.ENTITY_PLAYER,
    Entity = tear,
})
assert(damageContext.player == player and damageContext.isPlayerOwned,
    "damage context did not resolve the tear's parent player")

-- PRE_TEAR_COLLISION must return nil unless a module explicitly overrides it.
-- Returning true here makes every tear ignore enemies; returning false also
-- skips the game's internal damage code.
local Manager = dofile("mod/framework/manager.lua")
Manager.Util = {
    safeCall = function(fn)
        fn()
        return true
    end,
}
Manager.hookTargets.onTearCollide = {}
assert(Manager:dispatchWithCancel("onTearCollide", tear, target, false, {}) == nil,
    "empty collision dispatch must preserve the engine default with nil")
Manager.hookTargets.onTearCollide = {
    {
        id = "collision_override_test",
        onTearCollide = function() return true end,
    },
}
assert(Manager:dispatchWithCancel("onTearCollide", tear, target, false, {}) == true,
    "explicit collision override was not propagated")

-- GetPtrHash must make the damage lock stable across separate Lua userdata
-- wrappers that refer to the same engine entity.
frame = 3000
Manager._lockFrame = -1
Manager._locks = {}
local firstWrapper = enemy(false)
local secondWrapper = enemy(false)
firstWrapper.ptrHash = 9001
secondWrapper.ptrHash = 9001
assert(Manager:dealDamage(firstWrapper, 1, 0, EntityRef(player)),
    "first framework damage call was incorrectly blocked")
assert(not Manager:dealDamage(secondWrapper, 1, 0, EntityRef(player)),
    "pointer-hash lock did not block the same engine entity twice in one frame")
frame = 3001
assert(Manager:dealDamage(secondWrapper, 1, 0, EntityRef(player)),
    "pointer-hash lock did not reset on the next logical frame")

print("Crude Salt regression tests passed.")
