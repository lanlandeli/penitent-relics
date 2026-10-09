# 新道具与玩法模块开发指南

本页用一个被动道具演示模块、内容、配置和测试的接入。
接口查 [框架参考](framework_api.md)，验证命令查 [工作流](agent_workflow.md)。

## 1. 先确定职责

| 想实现的规则 | 首选入口 |
|---|---|
| 伤害、射速、飞行等属性 | onEvaluateCache |
| 逐玩家的持续规则 | onPlayerUpdate |
| 主动道具使用 | onUseItem |
| 泪弹、激光、刀、炸弹命中规则 | onAttackHit 与必要的实体回调 |
| 敌人或房间规则 | onNpc*、onNewRoom、必要时 onUpdate |
| 只改变显示 | 对应 Render、独立 Sprite 或中性效果实体 |

写出未持有、正常触发、重复触发、失去道具、新房间和保存继续时的行为。
按功能选择适用路径；纯属性道具可直接从缓存回调开始。

## 2. 最小示例：被动增加伤害

示例演示每份道具增加固定伤害。接入时先检查名称、模块 ID 和内容 ID 是否可用。

新建 `mod/modules/example_relic/init.lua`：

```lua
local M = {
    id = "example_relic",
    name = "Example Relic",
    version = "1.0.0",
    description = "Increases damage while held.",
    category = "stats",
    config = {
        damageBonus = 1.0,
    },
}

function M:cfg(key, fallback)
    return self.manager:getConfig(self, key, fallback)
end

function M:onRegister(manager)
    self.itemId = Isaac.GetItemIdByName(self.name)
    if not self.itemId or self.itemId <= 0 then
        self.itemId = nil
        manager.Util.warn("Example Relic is missing from content/items.xml")
    end
end

function M:onEvaluateCache(player, cacheFlag)
    if cacheFlag ~= CacheFlag.CACHE_DAMAGE or not self.itemId then
        return
    end
    local count = player:GetCollectibleNum(self.itemId)
    if count == 0 then
        return
    end
    player.Damage = player.Damage + self:cfg("damageBonus") * count
end

return M
```

manager 与引擎回调由框架接入；模块实现业务方法。
代码注释、游戏文本和日志使用英文。

## 3. 注册代码、内容、图标和配置

1. 在 `mod/modules/manifest.lua` 现有数组末尾加入 `"example_relic",`，保留其他模块。
2. 搜索 `mod/content/items.xml` 的占用 ID。当前本地 ID 是 1000、1001、1002；
   下例使用 1003，接入时替换为检查后确认空闲的 ID。
3. 向现有 `<items gfxroot="gfx/items/" version="1">` 中添加：

```xml
<passive id="1003" name="Example Relic" description="A little stronger"
    gfx="example_relic.png" quality="1" cache="damage"/>
```

4. 准备 `mod/resources/gfx/items/collectibles/example_relic.png`，32×32、RGBA。
   沿用本仓库 collectible 路径约定，gfx 写文件名。
5. 在 `itempools.xml` 选定现有池内追加条目，例如：

```xml
<Item Name="Example Relic" Weight="1" DecreaseBy="1" RemoveOn="0.1"/>
```

6. 在 `info_display.xml` 的 collectibles 根节点内加入：

```xml
<collectible id="1003">
    <info text="+1 damage per copy"/>
</collectible>
```

这里使用与 items.xml 一致的本地 ID，按现有图鉴格式添加后在游戏中确认显示。
接入可选 EID 描述时，先检查 EID 是否存在。
7. 在 `mod/config.lua` 的 modules 表增加：

```lua
example_relic = {
    enabled = true,
    -- damageBonus = 1.0,
},
```

运行时和 giveitem 使用按名称解析得到的道具 ID；XML 本地 ID 用于内容注册。
新增配置项写明单位、范围及叠加含义；模块默认值是默认参数的唯一来源。
XML 的增量/替换语义需逐文件查证：[items.xml](https://cuerzor.github.io/IsaacDocs/rep/xml/items.html)。

## 4. 属性缓存怎样正确使用

在 XML 声明相关 cache；回调只处理对应的单个 CacheFlag，并在现有属性上贡献自己的值。
获得/移除道具后通过属性重算恢复，不能每帧强写，也不要在缓存回调中再次 EvaluateItems。
状态驱动的增减益在**状态改变时**执行：

```lua
player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
player:EvaluateItems()
```

同一状态不变时不重复刷新。恢复存档后的相关属性也要重算。
API 依据：[EvaluateItems](https://cuerzor.github.io/IsaacDocs/rep/EntityPlayer.html#evaluateitems)。

## 5. 主动道具与缺失的生命周期

主动道具使用 onUseItem，先比较 itemId；先实施规则，再按实际结果决定 Discharge。
useFlags、activeSlot、customVarData 和 rng 都是引擎传入的上下文；
不要假定只有主槽或每次操作只触发一次。重复使用与充能行为按具体设计测试。

只有框架没有该生命周期时才注册额外回调。例如仅用于观察新层的写法：

```lua
function M:onRegister(manager)
    manager:addCallback(ModCallbacks.MC_POST_NEW_LEVEL, function(_)
        if not manager:isEnabled(self.id) then
            return
        end
        manager.Util.safeCall(function()
            self:onNewLevel()
        end, "MC_POST_NEW_LEVEL(" .. self.id .. ")")
    end)
end

function M:onNewLevel()
    -- Reset module-owned floor state here.
end
```

这是替代性的注册片段；实际模块应合并到自己已有的 onRegister。
需要返回值时捕获业务结果再返回；失败返回 nil，不能 return safeCall(...)。
filter 的含义取决于具体回调，可能是 Type、Variant 或道具 ID，不能统一当作实体类型。

## 6. 攻击规则、概率与状态

先按 [攻击兼容清单](attack_compatibility.md) 选择原版与模组组合。
新增攻击登记来源、触发单位和伤害方式；新增命中效果逐项记录适配决定与测试结果。

- 使用 ctx.player 与 ctx.entity；伤害上下文可能缺字段，见接口参考。
- 初始化回调与发射回调可能先后触发同一实体，以 GetData 标记保证只投一次概率。
  Init 时尚不可用的数据可在首次有效 Update 补齐。
- 每次攻击、每次命中、每段持续武器的投概率规则需要分别定义。
- 玩法概率优先用回调提供的 rng 或 `player:GetCollectibleRNG(self.itemId)`；
  若自行创建 RNG，使用明确且非零的种子，不每次判定重置同一随机序列。
- math.random 与当前 randomAngleVector 不用于需要种子复现的玩法；
  Render 不消耗玩法 RNG。测试注入可控随机结果。
- 附带伤害走 dealDamage，命中前通知不能当成“敌人已死亡”。
- 同帧多发攻击与多个模块仍会并发；保留独立通道、幂等和重入检查。
- EntityPtr/业务标识解决跟踪与替换问题；任何清理都只清自己命名空间的数据。

API 依据：[RNG](https://cuerzor.github.io/IsaacDocs/rep/RNG.html)、
[GetCollectibleRNG](https://cuerzor.github.io/IsaacDocs/rep/EntityPlayer.html#getcollectiblerng)。

## 7. 完成交付

新增 `tests/test_example_relic.lua`，覆盖未持有、多份、缓存过滤、移除与重复重算。
涉及攻击时补兼容清单中的组合，涉及视觉时补坐标和清理检查。

下面保存为 `tests/test_example_relic.lua`，在完成第 2–3 节接入后从仓库根目录运行。
这个测试模拟道具数量与属性缓存，验证未持有、多份、移除和缓存过滤：

```lua
CacheFlag = { CACHE_DAMAGE = 1, CACHE_SPEED = 2 }
Isaac = { GetItemIdByName = function() return 1003 end }

local module = dofile("mod/modules/example_relic/init.lua")
local manager = {
    getConfig = function(_, target, key, fallback)
        local value = target.config[key]
        if value == nil then return fallback end
        return value
    end,
    Util = { warn = function(message) error(message) end },
}
module.manager = manager
module:onRegister(manager)

local copies = 0
local player = {
    Damage = 3.5,
    GetCollectibleNum = function() return copies end,
}

for _, count in ipairs({ 0, 1, 2, 0 }) do
    copies = count
    -- The engine restores base stats before each cache evaluation.
    player.Damage = 3.5
    module:onEvaluateCache(player, CacheFlag.CACHE_DAMAGE)
    assert(player.Damage == 3.5 + count, "Incorrect damage bonus")
end

copies = 1
player.Damage = 3.5
module:onEvaluateCache(player, CacheFlag.CACHE_SPEED)
assert(player.Damage == 3.5, "Unrelated cache flag changed damage")
print("Example Relic tests passed.")
```

按工作流完成代码检查，再部署验证新增道具的实际效果。
本例检查获得、多份持有和移除后的伤害；新增状态或攻击规则时再补对应场景。
版本随功能或修复更新，文档修改保持版本。
