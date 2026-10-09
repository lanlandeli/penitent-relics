# Trinity / 三位一体 — 玩法与实现契约

当前模块版本：2.7.3。本文描述现行规则；验收清单不等于已完成实测。
通用接口见 [框架参考](framework_api.md)，素材与表现见 [美术清单](trinity_assets.md)。

## 1. 核心规则

Trinity 是 Q4 被动道具：按 Father → Son → Spirit 轮转攻击，依次挂印并触发审判。

- 拾取授予三颗完整魂心（items.xml 的 soulhearts="6"），获得飞行。
- 射速增加 0.7 tears，经 CACHE_FIREDELAY 换算；不直接增加面板伤害。
- 内容本地 ID 为 1001，运行时按名称解析；进入 angel 池，现有权重参数为
  Weight=1、DecreaseBy=1、RemoveOn=0.1。
- 拾取文案为 “The Father, the Son and the Holy Spirit.”；机制说明维护于模块 EID 与
  [内置图鉴](../mod/content/info_display.xml)。

下表数值是默认配置，倍率基于这次命中传入的原始 amount：

| 位格 | 攻击属性 | 命中结果 |
|---|---|---|
| Father（0，暖白） | 泪弹视觉缩放 ×1.15 | 添加或刷新 Father 印记，不补伤害 |
| Son（1，金色） | 泪弹穿透 | 无 Father 印记时总倍率 ×1.5；有时 ×3，并添加或刷新 Son 印记 |
| Spirit（2，冰蓝） | 原生追踪，限武器支持的属性 | 无双印记时总倍率 ×2；同时存在 Father 与 Son 印记时触发审判 |

两个印记分别存于目标，持续 150 个逻辑帧（约 5 秒），独立到期、刷新不叠层。
Son 不能在缺少 Father 印记时单独挂印；Spirit 缺少任一印记都不能触发审判。
印记不存攻击者身份，审判伤害归属触发它的 Spirit 攻击来源。
Boss 使用相同规则，实际扣血仍受引擎伤害机制影响。

## 2. 武器适配与分配时机

| 攻击路径 | 位格分配与继承 |
|---|---|
| 泪弹 | onFireTear 分配；首次 onTearUpdate 兜底。同一实体只推进一次，多发中的独立泪弹各自推进 |
| 科技、科技 X、硫磺火 | 根激光在 onLaserInit 分配并登记，覆盖 OneHit 首次 Update 前的命中；Update 再维护属性和表现 |
| 持续激光及派生段 | 同帧同一直接拥有者的主激光共享 volley，每 8 个逻辑帧推进位格；子段动态继承根组 |
| 妈刀及派生刀 | 读取玩家独立的 8 帧时钟；接触、飞行、返回和刀雨均使用当前位格，不推进泪弹/激光计数器 |
| 炸弹 | 排除：不分配位格，不挂印、不增伤、不触发审判或专属表现 |

泪弹和根激光使用攻击计数器；妈刀使用独立时钟，不能改成所有武器共享一个计数器。
激光沿 Parent 与 SpawnerEntity 查找根；IsSampleLaser() 不能单独作为“等待 Parent”的理由。
子段继承根哈希，避免同一主光束重复补伤害。Spirit 激光离开该位格时，
只清除 Trinity 自己追加的 homing flag，保留原有追踪。

伤害来源为玩家时，激光结合框架的激光伤害分类与模块活动根激光记录恢复位格；
妈刀使用框架同帧碰撞提示。无法可靠恢复攻击实体、位格或持有者时跳过。
不得重新加入 IsFlying 门禁、刀速判断或投掷序号来驱动妈刀轮转。

## 3. 伤害与审判

模块通过 dealIncidental → manager:dealDamage 提交相对原命中的差额：

| 分支 | 主目标附带伤害 | 其他目标 |
|---|---|---|
| Son，无 Father 印记 | 0.5 × amount | 无 |
| Son，有 Father 印记 | 2 × amount | 无 |
| Spirit，无双印记 | 1 × amount | 无 |
| Spirit，双印记审判 | 4 × amount | 半径 80 内其他可受伤、非友好且存活的敌人，各 2 × amount |

审判替代 Spirit 普通补伤害，主目标不再承受 AOE；结束时只清除主目标的两个印记。
倍率不重新读取玩家面板，以保留武器本身的伤害修正。
这些是原伤害加附带伤害的设计倍率，不能保证原生护甲、无敌和其他伤害钩子后的实际扣血。

附带伤害来源使用 EntityRef(player)，通道为模块 ID 加攻击哈希；激光优先使用根哈希。
不要复用原始武器 EntityRef 引发后续帧递归。与 Crude Salt 的附带伤害使用不同模块通道。
去重范围和返回值见 [框架伤害边界](framework_api.md#5-附带伤害的边界)。

## 4. 配置与属性

完整默认值只维护于 [模块 config](../mod/modules/trinity/init.lua)，覆盖写入
[mod/config.lua](../mod/config.lua) 的 modules.trinity，读取统一经过 self:cfg()。
本文第 1–3 节列出玩法默认值；不在文档中复制整张配置表。

- sonMarkedDamageMult 是 Father 印记下对 sonDamageMult 的追加乘数，默认 1.5 × 2 = 3。
- markDuration、laserTierTicks、knifeTierTicks 使用逻辑帧，计时基于 Game():GetFrameCount()。

### 4.1 属性换算

- tearsBonus 通过 tears = 30 / (MaxFireDelay + 1) 换算，再将新 MaxFireDelay 限制为至少 0。
- 飞行和射速只在对应缓存、持有道具时应用，移除后由原生缓存重算恢复。
- 魂心由内容 XML 授予，不是运行期配置；表现参数见素材文档与模块默认值。

## 5. 状态与生命周期

### 5.1 状态所有权

全部私有键带 pr_trinity_ 前缀。准确键名和辅助函数以模块源码为准：

| 所有者 | 状态 | 边界 |
|---|---|---|
| 玩家 | counter、knife_clock_start、orbs、wings_applied | 攻击计数与妈刀时钟分离；光球保存 EntityPtr |
| 敌人 | father_mark / son_mark、father_icon / son_icon | 印记是到期帧号；图标是 EntityPtr |
| 攻击实体 | tier | 已分配泪弹不因 Update 再次推进 |
| 直接激光拥有者、激光 | laser_volley、laser_group、laser_root_hash、laser_homing_owned | 根组共享轮转与通道，区分自己追加的追踪 |
| 模块私有表 | 活动激光、审判与起射表现记录 | 跨帧实体引用安全检查；换房/新局清理 |

### 5.2 更新与重置

1. 攻击回调分配位格、维护属性；不预先放大原始碰撞伤害。
2. onAttackHit 按第 1–3 节挂印、补伤害或审判；只处理有效敌人和受支持攻击。
3. onUpdate 清除到期/死亡目标印记；没有持有者时清除印记与临时攻击表现。
4. onNewRoom 清理印记、审判、起射表现及活动激光，重置攻击计数和妈刀时钟，
   新房间从 Father 开始；环绕光球继续由玩家更新维护。
5. onGameStart（含继续游戏）执行运行期重置，并移除旧光球和翅膀外观。
6. 持有者死亡或失去道具时清理其光球、翅膀和妈刀时钟；无效实体引用及时丢弃。

表现失败不改变印记与伤害判定。实体与动画的坐标、时长和清理检查集中在
[Trinity 素材文档](trinity_assets.md)。

## 6. 维护与验收

修改前同时检索 [实现](../mod/modules/trinity/init.lua)、
[回归测试](../tests/test_trinity.lua)、相关内容 XML 和素材。
既有注册、资源与框架接口直接复用；通用检查及部署顺序见 [工作流](agent_workflow.md)。

以下是验收要求，当前自动覆盖范围须读测试断言，实机结果须另附构建与场景记录：

| 范围 | 必须覆盖 |
|---|---|
| 分配 | 无道具不生效；连续六次轮转；Fire/Update 幂等；多发独立推进 |
| 激光 | 同帧多根、8/16/24 tick、持续/永续、OneHit 首次 Update 前命中、Parent/Spawner 子段与 sample 根 |
| 激光属性 | 继承位格、根通道去重、只移除自己追加的 homing |
| 妈刀 | 独立时钟、接触/飞行/返回/刀雨同步；玩家来源恢复；提示消费后不递归 |
| 印记与倍率 | 所有伤害分支；只有 Son/只有 Father 均不能审判；刷新、独立到期、审判清印 |
| 目标与范围 | 普通敌人/Boss；多敌人状态独立；AOE 边界和主目标排除；炸弹完全排除 |
| 生命周期 | 死亡、失效引用、换房、新局/继续、失去道具、属性反复重算 |
| 组合 | 与 Crude Salt 同帧命中；不同攻击通道；附带伤害跨帧不递归 |
| 实机表现 | 拾取魂心/飞行/射速；位格可辨、双印记、审判和音效；激光移动、缩放与非零渲染偏移 |

当前文档不声称已完整实测所有组合；模组间颜色覆盖、原生伤害修正及来源恢复边界仍需目标构建验证。