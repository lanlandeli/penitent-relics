-- Crude Salt
-- A reusable item module for Penitent Relics.
--
-- Hit: store the enemy's movement direction immediately before the hit.
-- While active: if the enemy moves strongly against that stored direction for
-- several consecutive frames, shatter it. Bosses take 5x the owner's current
-- damage instead. Repeated hits update the stored direction without stacking.

local M = {
    id = "crude_salt",
    name = "Crude Salt",
    version = "7.4.0",
    category = "item",
    config = {
        baseChance = 0.40,
        maxLuck = 8.0,
        tearScale = 1.15,
        tearPulseInterval = 3,
        reverseCos = -0.5,
        graceFrames = 5,
        requireFrames = 3,
        minMoveSpeed = 0.25,
        markHeightPadding = 6,
        markSizeRatio = 0.90,
        markMinScale = 0.34,
        markMaxScale = 0.78,
        markBackstabOffset = 12,
        bossDamageMult = 5.0,
        normalFatalDamage = 1000000,
        statueFrames = 60,
        shatterEffectFrames = 16,
        shatterSizeRatio = 2.2,
        shatterMinScale = 0.40,
        shatterMaxScale = 2.25,
    },
}

local KEY_LAST_DIR = "pr_crude_salt_last_dir"
local KEY_DEBUFF = "pr_crude_salt_debuff"
local KEY_STATUE_PENDING = "pr_crude_salt_statue_pending"
local KEY_TEAR_ROLLED = "pr_crude_salt_tear_rolled"
local KEY_TEAR_ACTIVE = "pr_crude_salt_tear_active"

local MARK_ANM2 = "gfx/effects/crude_salt_mark.anm2"
local SHATTER_ANM2 = "gfx/effects/crude_salt_shatter.anm2"
local VISUAL_ENTITY_NAME = "Penitent Relics Crude Salt Visual"
local MARK_HALF_SIZE = 16

-- High color offset produces the pale, opaque look of an ice statue while the
-- slightly warm RGB tint keeps it visually distinct as salt.
local SALT_COLOR = Color(1.10, 1.02, 0.82, 1, 0.65, 0.58, 0.38)
local SALT_TEAR_COLOR = Color(0.88, 0.92, 0.82, 1, 0.45, 0.45, 0.38)
local SALT_TEAR_PULSE_COLORS = {
    Color(0.84, 0.87, 0.77, 1, 0.38, 0.37, 0.30),
    Color(0.91, 0.92, 0.80, 1, 0.48, 0.46, 0.36),
    Color(0.97, 0.96, 0.82, 1, 0.56, 0.53, 0.40),
    Color(0.89, 0.90, 0.79, 1, 0.44, 0.42, 0.34),
}

function M:cfg(key, fallback)
    return self.manager:getConfig(self, key, fallback)
end

function M:onRegister(manager)
    self.saltStatues = {}
    self.shatterEffects = {}
    self.saltMarks = {}
    self.itemId = Isaac.GetItemIdByName("Crude Salt")
    if not self.itemId or self.itemId < 1 then
        manager.Util.warn("Crude Salt registration failed: item name not found in content/items.xml")
        self.itemId = nil
        return
    end

    self.visualVariant = Isaac.GetEntityVariantByName(VISUAL_ENTITY_NAME)
    if not self.visualVariant or self.visualVariant < 1 then
        manager.Util.warn("Crude Salt visual entity is missing from content/entities2.xml; "
            .. "using EFFECT_NULL fallback")
        self.visualVariant = EffectVariant.EFFECT_NULL
    end

    manager.Util.log("Crude Salt ready, runtime ID=" .. tostring(self.itemId))
    Isaac.DebugString("[PenitentRelics] Crude Salt ready: giveitem c" .. tostring(self.itemId))

    -- The native pickup prompt carries only the thematic sentence; EID
    -- (External Item Descriptions) shows the mechanic breakdown. EID rewrites
    -- RegisterMod, so its mod context is already "Penitent Relics" when this runs.
    -- Missing EID falls back silently to the short native description.
    if EID and EID.addCollectible then
        EID:addCollectible(self.itemId,
            "↑ Salt attacks: 40% chance, up to 100% at 8 Luck\n\n"
            .. "Supports tears, lasers, Tech X, Brimstone, and Mom's Knife\n"
            .. "On hit: records the enemy's movement direction\n"
            .. "Reverse it for 3 frames → shattered:\n"
            .. "• Normal enemies: frozen into a salt statue\n"
            .. "• Bosses: 5x damage",
            "Crude Salt",
            "en_us")
    end
end

function M:onNewRoom()
    self.saltStatues = {}
    self.saltMarks = {}
    self:clearShatterEffects()
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
        self.manager.Util.warn("Crude Salt failed to spawn custom visual: " .. anm2Path)
        return nil
    end

    effect.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    effect.GridCollisionClass = GridCollisionClass.COLLISION_NONE
    effect:SetTimeout(-1)
    local sprite = effect:GetSprite()
    sprite:Load(anm2Path, true)
    sprite:Play(animation, true)
    return effect
end

function M:spawnSaltMark(target)
    local sprite = Sprite()
    sprite:Load(MARK_ANM2, true)
    sprite:SetFrame("Idle", 1)
    sprite:Stop()
    local record = {
        sprite = sprite,
        targetPtr = EntityPtr(target),
        position = target.Position,
        active = true,
    }
    self.saltMarks[#self.saltMarks + 1] = record
    return record
end

function M:removeSaltMark(mark)
    if mark then
        mark.active = false
    end
end

function M:getTargetVisualMetrics(target)
    local spriteScale = target.SpriteScale or Vector(1, 1)
    local sizeMulti = target.SizeMulti or Vector(1, 1)
    local size = math.max(target.Size or 20, 8)
    local radiusX = size * math.abs(spriteScale.X) * math.abs(sizeMulti.X)
    local radiusY = size * math.abs(spriteScale.Y) * math.abs(sizeMulti.Y)
    local renderOffset = (target.PositionOffset or Vector.Zero)
        + (target.SpriteOffset or Vector.Zero)
    return radiusX, radiusY, renderOffset
end

function M:getShatterPresentation(target)
    local radiusX, radiusY, renderOffset = self:getTargetVisualMetrics(target)
    local targetRadius = math.max(radiusX, radiusY)
    local scale = targetRadius * self:cfg("shatterSizeRatio", 2.2) / 96
    scale = math.max(
        self:cfg("shatterMinScale", 0.40),
        math.min(scale, self:cfg("shatterMaxScale", 2.25))
    )
    return {
        scale = scale,
        offset = Vector(renderOffset.X, renderOffset.Y),
    }
end

function M:spawnShatter(target, presentation)
    local shatter = self:spawnVisual(target.Position, target, SHATTER_ANM2, "Shatter")
    if not shatter then
        return nil
    end

    presentation = presentation or self:getShatterPresentation(target)
    local scale = presentation.scale
    shatter.SpriteScale = Vector(scale, scale)
    shatter.SpriteOffset = presentation.offset
    shatter.DepthOffset = (target.DepthOffset or 0) + 50
    self.shatterEffects[#self.shatterEffects + 1] = {
        ptr = EntityPtr(shatter),
        born = Game():GetFrameCount(),
        frames = self:cfg("shatterEffectFrames", 16),
    }
    return shatter
end

function M:updateShatterEffects(frame)
    for i = #self.shatterEffects, 1, -1 do
        local record = self.shatterEffects[i]
        local effect = record.ptr and record.ptr.Ref or nil
        if not effect or not effect:Exists() then
            table.remove(self.shatterEffects, i)
        elseif frame >= record.born + record.frames then
            effect:Remove()
            table.remove(self.shatterEffects, i)
        end
    end
end

function M:clearShatterEffects()
    for i = #self.shatterEffects, 1, -1 do
        local record = self.shatterEffects[i]
        local effect = record.ptr and record.ptr.Ref or nil
        if effect and effect:Exists() then
            effect:Remove()
        end
        table.remove(self.shatterEffects, i)
    end
end

function M:updateSaltMarks()
    local bleedFlag = EntityFlag and EntityFlag.FLAG_BLEED_OUT or nil
    for i = #self.saltMarks, 1, -1 do
        local mark = self.saltMarks[i]
        local target = mark.targetPtr and mark.targetPtr.Ref or nil
        local targetAlive = target and target:Exists() and not target:IsDead()
        local debuff = targetAlive and target:GetData()[KEY_DEBUFF] or nil
        if mark.active and targetAlive and debuff and debuff.markPtr == mark then
                local radiusX, radiusY, renderOffset = self:getTargetVisualMetrics(target)
                local targetRadius = math.max(radiusX, radiusY)
                local scale = targetRadius * self:cfg("markSizeRatio", 0.90) / 32
                scale = math.max(
                    self:cfg("markMinScale", 0.34),
                    math.min(scale, self:cfg("markMaxScale", 0.78))
                )
                local sprite = mark.sprite
                sprite.Scale = Vector(scale, scale)
                local direction = debuff.direction
                if direction then
                    sprite.Rotation = math.deg(math.atan(direction.Y, direction.X))
                end
                -- Keep the direction marker completely static. Non-looping
                -- animations can be culled by the engine before the next tick.
                sprite:SetFrame("Idle", 1)
                sprite:Stop()
                local x = 0
                -- Backstabber uses the target's bleed presentation. Keep the
                -- salt icon to one side while that presentation is active.
                if targetAlive and bleedFlag and target:HasEntityFlags(bleedFlag) then
                    x = -self:cfg("markBackstabOffset", 12) * math.max(scale, 0.7)
                end
                local iconHalfHeight = MARK_HALF_SIZE * scale
                local height = radiusY + self:cfg("markHeightPadding", 6) + iconHalfHeight
                mark.position = target.Position + renderOffset + Vector(x, -height)
        else
            mark.active = false
            table.remove(self.saltMarks, i)
        end
    end
end

local function movementDirection(entity, minimumSpeed)
    local velocity = entity.Velocity
    if velocity and velocity:Length() >= minimumSpeed then
        return velocity:Normalized()
    end
    return nil
end

function M:getTearChance(luck)
    local baseChance = self:cfg("baseChance", 0.40)
    local maxLuck = self:cfg("maxLuck", 8.0)
    local clampedLuck = math.max(0, math.min(luck or 0, maxLuck))
    if maxLuck <= 0 then
        return 1.0
    end
    return baseChance + (1.0 - baseChance) * (clampedLuck / maxLuck)
end

function M:rollSaltTear(tear, ctx)
    local data = tear:GetData()
    if data[KEY_TEAR_ROLLED] then
        return data[KEY_TEAR_ACTIVE] == true
    end
    data[KEY_TEAR_ROLLED] = true

    local player = ctx and ctx.player or nil
    if not player or not player:HasCollectible(self.itemId) then
        return false
    end

    local chance = self:getTearChance(player.Luck)
    if tear:GetDropRNG():RandomFloat() >= chance then
        return false
    end

    data[KEY_TEAR_ACTIVE] = true
    tear:SetColor(SALT_TEAR_COLOR, -1, 100, false, false)
    local sprite = tear:GetSprite()
    local scale = self:cfg("tearScale", 1.15)
    sprite.Scale = sprite.Scale * scale
    return true
end

function M:rollSaltWeaponHit(player)
    local chance = self:getTearChance(player.Luck)
    return player:GetCollectibleRNG(self.itemId):RandomFloat() < chance
end

function M:onFireTear(tear, ctx)
    self:rollSaltTear(tear, ctx)
end

function M:onTearInit(tear, ctx)
    self:rollSaltTear(tear, ctx)
end

function M:onTearUpdate(tear, ctx)
    local data = tear:GetData()
    if not data[KEY_TEAR_ACTIVE] then
        return
    end

    local interval = self:cfg("tearPulseInterval", 3)
    if interval > 0 and tear.FrameCount % interval == 0 then
        local index = math.floor(tear.FrameCount / interval)
            % #SALT_TEAR_PULSE_COLORS + 1
        tear:SetColor(SALT_TEAR_PULSE_COLORS[index], interval + 1, 100, false, false)
    end
end

function M:onAttackHit(target, amount, damageFlags, source, countdownFrames, ctx)
    if not self.itemId
        or not target
        or not target:IsEnemy()
        or target:IsDead() then
        return
    end
    if not ctx
        or (ctx.type ~= "tear" and ctx.type ~= "laser" and ctx.type ~= "knife") then
        return
    end

    local player = ctx.player
    if not player or not player:HasCollectible(self.itemId) then
        -- EntityRef can lose its entity pointer while retaining SpawnerType.
        -- Falling back to a holder also supports the common single-player case.
        player = self.manager:findPlayerWithCollectible(self.itemId)
    end
    if not player or not player:HasCollectible(self.itemId) then
        return
    end

    if ctx.type == "tear" then
        if not ctx.entity or not ctx.entity:GetData()[KEY_TEAR_ACTIVE] then
            return
        end
    elseif not self:rollSaltWeaponHit(player) then
        return
    end

    local data = target:GetData()
    if data[KEY_STATUE_PENDING] then
        return
    end

    local frame = Game():GetFrameCount()
    local debuff = data[KEY_DEBUFF]
    if debuff then
        -- Permanent and unique: later salt attacks update the hit-time direction
        -- on the existing debuff instead of adding another stack.
        local direction = movementDirection(target, self:cfg("minMoveSpeed", 0.25))
            or data[KEY_LAST_DIR]
        if direction then
            debuff.direction = direction
        end
        debuff.owner = player
        debuff.graceUntil = frame + self:cfg("graceFrames", 5)
        debuff.reverseFrames = 0
        if not (debuff.markPtr and debuff.markPtr.active) then
            debuff.markPtr = self:spawnSaltMark(target)
        end
        self:updateSaltMarks()
        self.manager.Util.log("Crude Salt direction updated: " .. tostring(target.Type) .. "." .. tostring(target.Variant))
        return
    end

    -- MC_ENTITY_TAKE_DMG runs before damage is applied. The direction saved by
    -- onUpdate is therefore the last clean movement direction before knockback.
    local direction = data[KEY_LAST_DIR]
        or movementDirection(target, self:cfg("minMoveSpeed", 0.25))
    if not direction then
        -- A stationary entity has no meaningful facing vector; wait for a hit
        -- made while it is moving instead of inventing a direction.
        return
    end

    data[KEY_DEBUFF] = {
        direction = direction,
        owner = player,
        graceUntil = frame + self:cfg("graceFrames", 5),
        reverseFrames = 0,
        markPtr = self:spawnSaltMark(target),
    }
    self:updateSaltMarks()
    self.manager.Util.log("Crude Salt applied: " .. tostring(target.Type) .. "." .. tostring(target.Variant))
end

function M:onUpdate()
    if not self.itemId then
        return
    end

    local frame = Game():GetFrameCount()
    local hasHolder = self.manager:anyPlayerHasCollectible(self.itemId)
    local entities = Isaac.GetRoomEntities()
    self:updateSaltStatues(frame, entities)
    self:updateShatterEffects(frame)
    self:updateSaltMarks()

    for i = 1, #entities do
        local entity = entities[i]
        if entity and entity:IsEnemy() and not entity:IsDead()
            and entity.Type ~= EntityType.ENTITY_FROZEN_ENEMY then
            local data = entity:GetData()
            if not data[KEY_STATUE_PENDING] then
                local debuff = data[KEY_DEBUFF]
                if debuff then
                    self:tickDebuff(entity, data, debuff, frame)
                end

                -- Always accept the latest direction. Freezing the historical
                -- direction here was the old bug: a later hit could preserve a
                -- direction from the beginning of the room instead of hit time.
                if hasHolder and not data[KEY_DEBUFF] then
                    local direction = movementDirection(entity, self:cfg("minMoveSpeed", 0.25))
                    if direction then
                        data[KEY_LAST_DIR] = direction
                    end
                end
            end
        end
    end
end

function M:onRender()
    for i = 1, #self.saltMarks do
        local mark = self.saltMarks[i]
        local target = mark.targetPtr and mark.targetPtr.Ref or nil
        if mark.active and target and target:Exists() and not target:IsDead() then
            mark.sprite:Render(
                Isaac.WorldToScreen(mark.position),
                Vector.Zero,
                Vector.Zero
            )
        end
    end
end

local function isNativeSaltStatue(entity, initSeed)
    if not entity or not entity:Exists() or entity.InitSeed ~= initSeed then
        return false
    end
    if entity.Type == EntityType.ENTITY_FROZEN_ENEMY or entity:IsDead() then
        return true
    end
    return EntityFlag.FLAG_FREEZE
        and entity:HasEntityFlags(EntityFlag.FLAG_FREEZE)
end

function M:removeSaltStatueRecord(index, record, source, entities)
    if source and isNativeSaltStatue(source, record.initSeed) then
        self:spawnShatter(source, record.shatterPresentation)
    end

    local removed = {}
    local function removeCandidate(candidate)
        if not isNativeSaltStatue(candidate, record.initSeed) then
            return
        end
        local candidateHash = GetPtrHash(candidate)
        if removed[candidateHash] then
            return
        end
        removed[candidateHash] = true
        candidate:Remove()
    end

    removeCandidate(source)
    removeCandidate(record.ptr and record.ptr.Ref or nil)
    for i = 1, #(entities or {}) do
        removeCandidate(entities[i])
    end
    table.remove(self.saltStatues, index)
end

function M:onPlayerCollide(player, collider, low)
    if not collider then
        return nil
    end
    for i = #self.saltStatues, 1, -1 do
        local record = self.saltStatues[i]
        if isNativeSaltStatue(collider, record.initSeed) then
            self:removeSaltStatueRecord(i, record, collider, Isaac.GetRoomEntities())
            -- Ignore the native frozen-enemy kick so it cannot become an ice tear.
            return true
        end
    end
    return nil
end

function M:updateSaltStatues(frame, entities)
    for i = #self.saltStatues, 1, -1 do
        local record = self.saltStatues[i]
        local tracked = record.ptr and record.ptr.Ref or nil

        -- Frozen death can replace the source entity. Prefer a FrozenEnemy
        -- with the same InitSeed and refresh the safe pointer when found.
        for j = 1, #entities do
            local candidate = entities[j]
            if isNativeSaltStatue(candidate, record.initSeed) then
                if not tracked or not tracked:Exists()
                    or candidate.Type == EntityType.ENTITY_FROZEN_ENEMY then
                    tracked = candidate
                    record.ptr = EntityPtr(candidate)
                end
            end
        end

        if frame >= record.removeAt then
            local disappearSource = isNativeSaltStatue(tracked, record.initSeed) and tracked or nil
            if not disappearSource then
                for j = 1, #entities do
                    if isNativeSaltStatue(entities[j], record.initSeed) then
                        disappearSource = entities[j]
                        break
                    end
                end
            end
            if disappearSource then
                self:removeSaltStatueRecord(i, record, disappearSource, entities)
            else
                table.remove(self.saltStatues, i)
            end
        elseif tracked and tracked:Exists() then
            local remaining = math.max(record.removeAt - frame, 2)
            tracked:SetColor(SALT_COLOR, remaining, 100, false, true)
        end
    end
end

function M:tickDebuff(entity, data, debuff, frame)
    if entity:IsDead() then
        data[KEY_DEBUFF] = nil
        return
    end
    if frame < debuff.graceUntil then
        return
    end

    local current = movementDirection(entity, self:cfg("minMoveSpeed", 0.25))
    if current and current:Dot(debuff.direction) <= self:cfg("reverseCos", -0.5) then
        debuff.reverseFrames = debuff.reverseFrames + 1
    else
        debuff.reverseFrames = 0
    end

    if debuff.reverseFrames >= self:cfg("requireFrames", 3) then
        data[KEY_DEBUFF] = nil
        self:triggerShatter(entity, data, debuff)
    end
end

function M:triggerShatter(entity, data, debuff)
    local owner = debuff.owner
    Isaac.DebugString(
        "[PenitentRelics] Crude Salt triggered enemy "
            .. tostring(entity.Type) .. "." .. tostring(entity.Variant)
            .. " boss=" .. tostring(entity:IsBoss())
    )

    if entity:IsBoss() then
        self:removeSaltMark(debuff.markPtr)
        self:spawnShatter(entity)
        local damage = owner.Damage * self:cfg("bossDamageMult", 5.0)
        self.manager:dealDamage(entity, damage, 0, EntityRef(owner))
        return
    end

    local statueFrames = self:cfg("statueFrames", 60)
    self:removeSaltMark(debuff.markPtr)
    data[KEY_STATUE_PENDING] = true
    table.insert(self.saltStatues, {
        ptr = EntityPtr(entity),
        initSeed = entity.InitSeed,
        removeAt = Game():GetFrameCount() + statueFrames,
        shatterPresentation = self:getShatterPresentation(entity),
    })

    -- Let the engine own lethal resolution, drops and room-clear state.
    entity:AddFreeze(EntityRef(owner), statueFrames)
    -- FLAG_FREEZE only immobilizes. FLAG_ICE is the native death marker that
    -- instructs the engine to replace a lethal victim with FrozenEnemy.
    entity:AddEntityFlags(EntityFlag.FLAG_ICE)
    entity:SetColor(SALT_COLOR, statueFrames, 100, false, true)
    self.manager:dealDamage(
        entity,
        math.max(self:cfg("normalFatalDamage", 1000000), 1000000),
        DamageFlag.DAMAGE_IGNORE_ARMOR,
        EntityRef(owner)
    )
    Isaac.DebugString(
        "[PenitentRelics] Crude Salt native frozen statue started "
            .. tostring(entity.Type) .. "." .. tostring(entity.Variant)
    )
end

return M
