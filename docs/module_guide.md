# 新道具与玩法模块开发指南

从根目录 [AGENTS.md](../AGENTS.md) 开始。
本教程负责“如何接入”，完整签名查 [framework_api.md](framework_api.md)，
模块边界查 [architecture.md](architecture.md)，验证命令查 [agent_workflow.md](agent_workflow.md)。

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
不涉及的路径标“不适用”，不用为纯属性道具创建攻击状态机。

## 2. 最小示例：被动增加伤害

以下示例尚未注册进项目；名字、模块 ID 和内容 ID 在实际接入前必须重新搜索。
它只演示每份道具增加固定伤害，不引入额外框架。

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

模块不赋值 manager，不再次 RegisterMod，不直接注册已覆盖的引擎回调。
代码注释、游戏文本和日志使用英文。

## 3. 注册代码、内容、图标和配置

1. 在 `mod/modules/manifest.lua` 现有数组末尾加入 `"example_relic",`，保留其他模块。
2. 搜索 `mod/content/items.xml` 的占用 ID。当前本地 ID 是 1000、1001、1002；
   下例 1003 仅在仍未被使用时可用。1000 起始是仓库约定，不是引擎的通用安全范围。
3. 向现有 `<items gfxroot="gfx/items/" version="1">` 中添加：

```xml
<passive id="1003" name="Example Relic" description="A little stronger"
    gfx="example_relic.png" quality="1" cache="damage"/>
```

4. 准备 `mod/resources/gfx/items/collectibles/example_relic.png`，32×32、RGBA。
   沿用本仓库 collectible 路径约定，gfx 写文件名；不要照着旧教程放到 mod/gfx。
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

这里使用与 items.xml 一致的本地 ID。该图鉴格式沿用现有项目内容；
本次公开资料未查到完整 schema，必须在目标游戏验证显示。
如果提供可选 EID 描述，先判定 EID 存在，不能将其变成依赖。
7. 在 `mod/config.lua` 的 modules 表增加：

```lua
example_relic = {
    enabled = true,
    -- damageBonus = 1.0,
},
```

运行时始终使用按名称获得的道具 ID；不能把 XML 本地 ID 当作 giveitem 的运行时 ID。
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

新增 `tests/test_example_relic.lua`，至少验证未持有、持有一份/多份、错误 CacheFlag、
移除后重算，以及重复重算不累积。涉及状态、伤害和视觉时补对应矩阵。
示例只展示接口结构；接入后的测试需要真实断言，不能只有永远成功的空 mock。

运行工作流中的全量验证。通过后才部署到本地测试游戏，再做获得/移除、换房、
保存继续、与既有道具组合的实测。记录游戏版本、场景、结果及未覆盖项。
版本只随功能/修复改变；单纯文档修改不提升模组版本。