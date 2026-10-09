# Penitent Relics 协同开发规范

本文件是 Penitent Relics 开发者及智能体协作的最高优先级工程契约。它适用于整个仓库。
任何代码、资源、测试或文档修改都必须遵守本文件；若其他项目文档与本文件冲突，以本文件为准。

相关专题文档：

- `docs/framework_api.md`：已实现的生命周期、攻击上下文和公共工具边界
- `docs/api_research.md`：API 查证来源、日期和未验证事项
- `docs/code_style.md`：Lua 格式、命名和语言细则
- `docs/architecture.md`：通用道具框架的产品边界、分层和兼容策略
- `docs/module_guide.md`：道具及玩法模块的入门教程和美术资源流程
- `docs/custom_visuals.md`：自定义视觉效果开发标准（实体变体注册、动画、清理、音效）
- `docs/agent_workflow.md`：智能体强制工作流（搜索、API 查证、兼容矩阵、视觉验收、部署）
- `README.md`：安装、部署和玩家侧说明

## 1. 项目目标与设计原则

暂不考虑联机实现。

Penitent Relics（忏悔遗物）是一个可持续加入多种原版风格道具的 Repentance+
内容扩展模组。道具可以修改属性、主动使用、攻击、敌人、房间规则或视觉表现。它不是围绕单个
道具编写的一次性脚本。所有实现必须满足以下原则：

运行时基线为 **Repentance+ 原生 Lua API**，不要求脚本扩展器。标准 API 无法可靠表达的效果
必须调整产品契约或停止实现，不得退回“取消原事件再重放”或其他破坏组合安全的方案。

1. **模块独立**：一个道具的故障不能阻止其他道具加载或运行。
2. **框架统一**：游戏回调、攻击者解析、配置、标记和附加伤害通过框架处理。
3. **组合安全**：默认假设多个道具和多个实体会在同一帧共同触发。
4. **引擎优先**：死亡、掉落、房间清除和伤害结算优先交给游戏原生系统。
5. **兼容优先**：不得依赖未记录的 userdata 身份、长期失效实体引用或回调副作用。
6. **可验证**：状态机和公共接口必须能在脱离游戏的 Lua 5.3 测试中验证。

Isaac API 首选 `https://cuerzor.github.io/IsaacDocs/rep/` 的社区文档；缺失时查英文上游或游戏随附资料。修改引擎交互前必须核对目标类、
方法、回调签名、返回值和版本说明，不凭记忆猜测 API。

## 2. 目录边界与修改权限

```text
mod/
├── main.lua                  # 唯一入口，只做兼容检查与框架初始化
├── config.lua                # 全局开关和模块配置覆盖
├── framework/                # 公共基础设施和稳定接口
├── modules/                  # 道具及玩法模块
│   ├── manifest.lua          # 模块注册清单
│   └── <module_id>/          # 每个道具/玩法模块的私有实现与资源逻辑
├── content/                  # 道具、道具池等 XML 内容注册
└── resources/                # 游戏运行时资源
tests/                        # 脱离游戏运行的 Lua 回归测试
tools/                        # 检查、部署和资源生成工具
docs/                         # 面向开发者和用户的专题文档
```

协作边界：

- 开发普通道具或玩法模块时，只修改自己的 `modules/<module_id>/`、对应测试、配置和必要资源。
- 不为单一道具修改 `framework/`；只有至少两个模块需要相同能力时才考虑提取公共接口。
- 修改 `framework/`、生命周期签名、攻击上下文或配置语义属于接口变更，必须同步所有调用方、
  测试和文档，并在交接说明中单独列出。
- `manifest.lua`、`config.lua`、内容 XML 是高冲突共享文件。修改应保持最小化，不进行无关排序或格式化。
- 不覆盖、不回退、不删除其他开发者未合并的修改。发现同文件并行修改时先划分代码区块或协调合并。
- 游戏目录只接收通过验证的 `mod/` 内容；源码、测试、工具和文档不得部署进去。

## 3. 模块定义接口

每个模块位于 `mod/modules/<module_id>/init.lua`，并返回一个模块表：

```lua
local M = {
    id = "my_item",
    name = "My Item",
    version = "1.0.0",
    description = "A concise English description.",
    category = "item",
    config = {
        enabledFeature = true,
        durationFrames = 60,
    },
    customVariantName = nil,
}

function M:cfg(key, fallback)
    return self.manager:getConfig(self, key, fallback)
end

function M:onRegister(manager)
    -- Resolve runtime IDs and initialize module-owned state here.
end

return M
```

字段约定：

| 字段 | 要求 | 说明 |
|---|---|---|
| `id` | 必填 | 小写英文和下划线，必须与目录及 manifest 条目一致 |
| `name` | 必填 | 英文显示名 |
| `version` | 必填 | `MAJOR.MINOR.PATCH` |
| `description` | 建议 | 英文，描述可观察行为而不是实现 |
| `category` | 建议 | 主职责：`item`、`active`、`stats`、`combat`、`world` 或 `visual`；仅作元数据 |
| `config` | 可选 | 模块默认值；不得在运行时修改该表 |
| `customVariantName` | 可选 | 与内容 XML 中注册的实体名称一致 |
| `manager` | 框架注入 | 模块不得自行赋值或缓存另一份 Manager |

新模块还必须在 `mod/modules/manifest.lua` 注册。模块不得 `include()` 或读写另一个玩法模块的
私有实现；跨模块能力必须提升为明确的框架接口。

## 4. 生命周期接口

模块只实现需要的回调。除 `onRegister` 外，以下回调都由 Manager 的预编译分发表调用并进行
模块级错误隔离：

| 回调 | 参数 | 返回值契约 |
|---|---|---|
| `onRegister` | `(manager)` | 无；无论模块是否启用都会调用一次 |
| `onGameStart` | `(continued)` | 无 |
| `onNewRoom` | `()` | 无 |
| `onUpdate` | `()` | 无 |
| `onRender` | `()` | 无 |
| `onPlayerUpdate` | `(player)` | 无；玩家逐帧被动效果优先使用，模块自行检查道具持有 |
| `onEvaluateCache` | `(player, cacheFlag)` | 无；模块自行过滤 cacheFlag 并检查道具持有，只修改自己负责的属性 |
| `onUseItem` | `(itemId, rng, player, useFlags, activeSlot, customVarData)` | 默认 `nil`；主动道具可返回布尔值或 `{ Discharge, Remove, ShowAnim }` |
| `onFireTear` | `(tear, ctx)` | 无 |
| `onTearInit` | `(tear, ctx)` | 无 |
| `onTearUpdate` | `(tear, ctx)` | 无 |
| `onTearRender` | `(tear, offset, ctx)` | 无 |
| `onAttackHit` | `(target, amount, dmgFlags, source, countdownFrames, ctx)` | 无 |
| `onTearHit` | `(tear, target, amount, dmgFlags, source, ctx)` | 无 |
| `onTearCollide` | `(tear, target, low, ctx)` | 默认 `nil`；仅明确覆盖原生碰撞时返回布尔值 |
| `onPlayerCollide` | `(player, collider, low)` | 默认 `nil`；仅明确覆盖时返回布尔值 |
| `onNpcCollide` | `(npc, collider, low)` | 默认 `nil`；仅明确覆盖时返回布尔值 |
| `onNpcInit` | `(npc)` | 无 |
| `onNpcUpdate` | `(npc)` | 默认 `nil`；返回 `true` 会跳过原生 NPC 更新 |
| `onLaserInit/Update` | `(laser, ctx)` | 无 |
| `onLaserRender` | `(laser, offset, ctx)` | 无 |
| `onBombInit/Update` | `(bomb, ctx)` | 无 |
| `onBombRender` | `(bomb, offset, ctx)` | 无 |
| `onKnifeInit/Update` | `(knife, ctx)` | 无 |
| `onKnifeRender` | `(knife, offset, ctx)` | 无 |

碰撞回调中 `nil`、`true` 和 `false` 都可能有不同的引擎含义。不得用 `false` 代替“无决定”，
不得为了“保险”返回固定布尔值。

`onUseItem` 会接收所有主动道具使用事件，模块必须先比较自己的运行时道具 ID。多个模块返回
非 `nil` 时按 manifest 顺序分发，最后一个返回值生效；只观察其他主动道具时必须返回 `nil`。

只有 `onUseItem` 当前保证 manifest 顺序；其他事件通过 `pairs` 构建分发表，顺序不保证。
有返回值事件在模块分发中取最后一个非 nil 值，不能据此推导引擎所有回调的执行规则。
`safeCall` 只捕获 Lua 异常，不回滚副作用，也不防止原生崩溃；注册失败不会自动禁用模块。

只有框架确实没有对应生命周期时，模块才能使用 `manager:addCallback()`。额外回调必须在
`onRegister` 注册，必须处理游戏传入的首个 mod 参数，并自行通过 `manager.Util.safeCall()`
隔离运行期错误，并自行检查 `manager:isEnabled(self.id)`。有返回值时单独保存业务结果，不能返回 safeCall 的成功布尔值。若第二个模块也需要同一回调，应把它提升到 `hooks.lua` 生命周期接口。

## 5. 攻击上下文契约

不要在模块里重复解析 `Parent`、`SpawnerEntity` 或熟悉物所有者。以下为攻击实体生命周期的 `ctx` 示例，不代表所有伤害上下文都具备这些字段：

```lua
ctx = {
    type = "tear",          -- tear / laser / knife / bomb
    player = playerOrNil,
    isPlayerOwned = true,
    weaponType = weaponType,
    variant = variant,
    isSpecial = false,
    entity = attackEntity,
    tear = tearOrNil,
    laser = laserOrNil,
    knife = knifeOrNil,
    bomb = bombOrNil,
}
```

`onAttackHit` 的普通伤害上下文不保证提供 weaponType、isSpecial 或 tear/laser/knife/bomb 别名，也可能缺少 ctx.player 或 ctx.entity；完整字段差异见 docs/framework_api.md。
模块应先使用 `ctx.player`，确有需要时再用 `manager:findPlayerWithCollectible(itemId)` 兜底。
`findPlayerWithCollectible` 只证明持有，不证明攻击来源；缺少归属时按模块设计跳过或有限兜底。

原版妈刀接触伤害可能把玩家而非刀实体写入 `EntityRef.Entity`。框架通过
`MC_PRE_KNIFE_COLLISION` 暂存同帧的“刀+目标”安全引用，并在伤害回调中恢复 `ctx.entity`；
该提示必须在首次恢复时消费，防止模块提交的玩家来源附带伤害递归进入妈刀命中。

## 6. 框架公共接口

模块可以依赖下列稳定接口：

| 接口 | 用途 |
|---|---|
| `manager:getConfig(module, key, fallback)` | 读取合并后的静态配置 |
| `manager:setMark(moduleId, entity)` | 在实体 `GetData()` 中写入模块归属标记 |
| `manager:hasMark(moduleId, entity)` | 检查模块归属标记 |
| `manager:dealDamage(target, amount, dmgFlags, source[, channel])` | 提交附带伤害并进行同帧去重；true 仅表示已调用 TakeDamage，不证明扣血；`channel` 可选字符串（建议 `模块id..":"..GetPtrHash(攻击实体)`），锁键为"目标+channel"，不同模块/攻击实体同帧可独立结算；省略时保持旧行为 |
| `manager:findPlayerWithCollectible(itemId)` | 查找持有道具的玩家作为有限兜底 |
| `manager:anyPlayerHasCollectible(itemId)` | 只判断是否至少一名玩家持有道具 |
| `manager:isEnabled(id)` | 查询模块启用状态 |
| `manager:dispatchWithResult(event, ...)` | 框架内部的有返回值生命周期分发；普通模块不得主动调用 |
| `manager:addCallback(callbackId, fn, filter)` | 注册框架尚未覆盖的特殊回调 |
| `manager:addPriorityCallback(callbackId, priority, fn[, filter])` | 以明确的原生优先级注册特殊回调 |
| `manager.Util.log/warn` | 统一日志 |
| `manager.Util.safeCall(fn, context)` | 捕获 Lua 错误，只返回成功布尔值 |
| `manager.Variants:getByEffect(moduleId)` | 查询 customVariantName 的既有变体映射 |
| `manager.Util.hsvColor` | 颜色转换 |
| `manager.Util.angleToVector/randomAngleVector` | 向量工具 |

不得从模块直接修改 `manager.modules`、`enabled`、`hookTargets`、`_locks` 或任何以下划线
表示的内部状态。公共接口的参数或返回语义不得静默改变。

## 7. 实体、状态和伤害安全

这是最容易导致崩溃或跨模块污染的部分，必须严格遵守：

1. 实体局部状态存入 `entity:GetData()`，键使用 `pr_<module_id>_<name>`。
2. 跨回调表索引使用 `GetPtrHash(entity)`，不得用 Entity userdata 直接作为 table key。
3. 跨帧引用使用 `EntityPtr(entity)`；每次读取 `.Ref` 后重新检查是否为 `nil`、`Exists()`。
4. 若原生机制会替换实体，使用明确的业务标识（如 `InitSeed`）查找替代实体，不能假设引用延续。
5. 操作目标前依次判断引用存在、`Exists()`、类型是否符合、是否已经 `IsDead()`。
6. 敌人判断使用 `IsEnemy()`；Boss 判断使用 `IsBoss()`，不得假设存在 `ENTITY_MONSTER`。
7. 模块的附带伤害只能调用 `manager:dealDamage()`，不得直接 `TakeDamage()`。
8. 不以 `Kill()`、`Die()` 或 `Remove()` 代替正常致命伤害，除非需求明确就是移除非战斗实体。
9. `MC_ENTITY_TAKE_DMG` 在伤害应用前触发；模块默认返回 `nil`，不得返回布尔值阻断其他模组，
   也不得取消并重放原伤害。
10. 永久状态也必须定义清理条件，例如死亡、新房间、新游戏或实体引用失效。
11. 自定义视觉必须使用 `content/entities2.xml` 注册的中性效果变体（运行时
    `Isaac.GetEntityVariantByName()` 解析）；不得用 `POOF01` 等原生效果变体
    承载自定义 ANM2——引擎会保留原生行为导致动画不生效。详见
    `docs/custom_visuals.md`。

模块键、标记和生成实体必须带模块命名空间，不能复用其他模块的私有键。

## 8. 配置、内容与资源规范

- 配置为会话内静态浅合并，首次读取后缓存；`enabled` 仅由全局覆盖控制。禁用不移除内容 XML，也不自动注销额外回调。
- 可调行为写在模块 `config` 默认表，项目覆盖写在 `mod/config.lua` 的 `modules.<id>`。
- 读取配置统一走 `self:cfg()` 或 `manager:getConfig()`；不在逻辑中复制“魔法默认值”。
- 新增配置项时同步模块默认值、全局覆盖示例和必要测试。
- 游戏内名称、描述、日志、Lua/XML/ANM2 注释和资源名称必须是英文。
- 面向项目成员的 Markdown 文档可以使用中文。
- 内容 XML 的内部 ID 必须先检查现有占用；不得为了整理而重编号已发布内容。
- PNG 使用游戏可读取的标准 RGBA 格式；ANM2 中的路径大小写必须与部署文件一致。
- 资源属于使用它的模块。共享资源必须有明确通用语义，不能以某个道具名伪装成公共资源。
- 不直接编辑游戏目录。只修改仓库中的 `mod/`，验证后使用部署脚本镜像复制。

需要保存继续的状态不能只放 GetData；只序列化纯数据，记录格式版本和恢复流程。
当前 Forbidden Fruit 是现有模组存档写入者，第二个模块需要存档时必须先设计公共命名空间与迁移，
不得各自调用 SaveData 覆盖同一份数据。参见 docs/architecture.md。

## 9. Lua 与代码风格

- 项目代码保持 Lua 5.3 兼容子集，并使用 Lua 5.3 离线测试；不得依赖更新版本的专属功能。
  禁止 `unpack`、`loadstring`、`getfenv/setfenv` 等
  5.1 遗留接口。
- 缩进使用 4 个空格，不使用 tab；Lua 行宽尽量不超过 100 字符。
- 函数、字段使用 `lowerCamelCase`，局部常量使用 `UPPER_SNAKE_CASE`。
- 函数保持单一职责。复杂模块按“判定、状态更新、表现、清理”拆分私有方法。
- 优先早返回，减少深层嵌套；不在每帧回调里构造不必要的表、字符串或全房间扫描。
- 注释解释引擎约束和设计原因，不复述语句本身；不得保留被注释掉的旧实现。
- 日志使用 `[PenitentRelics]` 体系，不在模块中散落无前缀 `print()`。
- 玩法概率使用有明确种子的 RNG；不在 Render 消耗玩法随机数，不以 math.random 代替可复现的规则判定。
- 不引入全局变量。模块常量、辅助函数和状态默认使用 `local`。
- 一次修改只包含当前任务需要的格式变化，避免制造无关 diff。

## 10. 测试契约

每个包含状态机、概率、伤害、实体替换、主动道具返回值或碰撞语义的模块必须有
`tests/test_<module_id>.lua`。
测试至少覆盖：

- 未持有道具或未触发概率时不产生效果；
- 正常触发路径；
- Boss 与普通敌人的差异；
- 重复命中、同帧触发和状态刷新；
- 死亡、失效引用、换房间等清理路径；
- 公共接口变更对应的框架回归测试。

Mock 只模拟测试所需的最小 Isaac API。新增引擎调用时，测试桩必须体现其关键语义，
不能写一个永远成功的空函数掩盖错误。

提交或交接前必须执行全量语法检查、所有 `tests/test_*.lua` 和 `git diff --check`。
具体 PowerShell 命令统一维护在 `docs/agent_workflow.md` 第 5 节；任一失败立即停止。
当前有 framework、main、crude_salt、trinity、forbidden_fruit 五个测试文件，新增文件自动纳入。

不得只执行手写的旧测试列表。修改 XML 或 ANM2 后还要进行 XML 解析检查；修改图片后确认
尺寸、色彩模式和引用路径。自动测试不能替代游戏内验证，涉及碰撞、死亡替换、渲染和音效时，
必须记录实际验证场景与结果。

## 11. 开发者与智能体工作流

智能体开始任何实现前必须完整执行 `docs/agent_workflow.md` 的强制顺序。尤其不得跳过：

- 修改前搜索仓库中的现有实现、调用方、测试、资源和未提交差异；
- 修改 Isaac 引擎交互前核对目标版本 API；
- 攻击特效先填写泪弹、科技、科技 X、硫磺火、妈刀、炸弹和熟悉物适配矩阵；
- 自定义动画先确认坐标空间、RenderOffset、动画时长和全部清理路径；
- 自动验证通过后才部署，并核对游戏目录的版本或哈希。

任何“未搜索就新增框架逻辑”“未核对回调就猜签名”“只在大图上验收像素素材”均视为
未完成，不得部署。

开始任务前：

1. 阅读本文件、相关模块、现有测试和当前工作区差异。
2. 明确任务边界、预期行为、涉及文件和不应改变的行为。
3. 将工作拆成互不覆盖的单元；同一文件原则上只由一个参与者负责。
4. 若必须修改共享接口，先约定接口，再让各模块基于同一契约实现。

开发过程中：

- 保留用户及其他参与者的未提交改动，不使用破坏性 Git 命令清理工作区。
- 不假设其他任务已经完成；依赖尚未合并的接口时，在交接中明确记录。
- 不因局部需求复制框架逻辑。发现公共缺口时先提出最小接口设计。
- 每次修改后运行与其风险相称的检查，不把明显失败留给下一位开发者。

交接必须包含以下信息：

```text
目标：本次实现的可观察行为
查证：搜索过的文件、核对的 API 页面和关键事实
修改：涉及的文件和公共接口
不变量：刻意保持不变的兼容行为
验证：执行过的命令、游戏场景和结果
部署：是否部署，以及源/目标版本或哈希核对
风险：尚未在游戏内覆盖的边界情况
后续：下一位开发者可直接执行的具体事项
```

禁止只说“已修复”而不说明验证依据。禁止把未经验证的代码部署到游戏目录。

## 12. 接口变更与版本管理

接口变更包括生命周期参数、`ctx` 字段、Manager 公共方法、配置字段语义、GetData 键格式和
内容资源路径。进行接口变更时必须：

1. 说明旧行为、问题和新契约；
2. 搜索并更新仓库内全部调用方；
3. 增加兼容层或明确这是破坏性变更；
4. 更新本文件及相关专题文档；
5. 增加覆盖旧问题的回归测试；
6. 更新模块或模组版本号。

版本规则：修复使用 PATCH，向后兼容的新能力使用 MINOR，破坏现有模块接口使用 MAJOR。
不得仅为注释、测试或文档修改提升游戏模组版本。

## 13. 完成标准

一项功能只有同时满足以下条件才算完成：

- 行为符合需求，且没有改变无关道具或原生机制；
- 模块边界和公共接口符合本文件；
- Lua、XML/ANM2 和相关回归测试通过；
- 没有原始 Entity 长期引用、userdata 表键、直接附带伤害或无命名空间状态；
- 配置、英文游戏文本、资源和版本按需同步；
- 对碰撞、渲染或原生实体替换进行过游戏内验证，或明确标记尚未验证；
- 交接信息足以让另一名开发者无需猜测即可继续工作；
- 本地测试部署在自动验证通过后进行，再完成当前构建实机验收；发布交付须记录验收结果和剩余风险。只部署 `mod/`，部署前检查镜像删除影响并备份需保留的数据。
- 交接包含 `docs/agent_workflow.md` 模板要求的查证、部署核对和未实测风险。
