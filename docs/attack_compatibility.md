# 攻击兼容清单

新增攻击或命中效果时，用本页选测试场景、登记模组攻击并记录组合结果。
玩法数值写在模块设计中，接口签名查 [框架参考](framework_api.md)。

## 1. 怎样使用

1. **新增攻击**：在第 3 节登记来源、伤害、触发和清理方式，逐项检查现有命中效果能否作用于它。
2. **新增效果**：从第 2 节选择原版攻击，再检查第 3 节中的模组攻击。
3. **完成验证**：按第 4 节记录组合预期，在第 5 节留下测试或实机证据。

每项分别记录**适配决定**与**验证结果**：

| 适配决定 | 含义 |
|---|---|
| 接入 | 按该效果的规则参与触发 |
| 保持原行为 | 攻击照常工作，此效果不改变它 |
| 专用处理 | 使用单独的触发、倍率或表现规则，链接设计说明 |
| 待定 | 尚未确定规则或来源 |

验证结果写“未测 / 离线通过 / 实机通过 / 有问题”，并注明覆盖场景。
“未测”和“保持原行为”是两件事，分别填写。

## 2. 原版攻击检查表

下列覆盖 WeaponType 中的攻击类别，并补充熟悉物、持续伤害和接触伤害。
“路径”描述当前框架入口；“待查”表示先记录实体和伤害来源，再决定接入方式。

| 登记键 | 攻击或代表道具 | 当前路径 | 重点检查 |
|---|---|---|---|
| vanilla.tears | 普通泪弹 | tear | Fire/Init/Update 只初始化一次；穿透后的连续命中 |
| vanilla.monstro | Monstro's Lung | 按实际泪弹进入 tear | 一次蓄力生成多发：按发射批次还是每颗泪弹触发 |
| vanilla.ludovico | Ludovico Technique | 按实际泪弹进入 tear | 长驻实体、重复接触、重新进房后的状态 |
| vanilla.fetus | C Section | 待查具体实体与命中来源 | 胎儿攻击的连续命中、穿透、子攻击及归属 |
| vanilla.technology | Technology | laser | OneHit 在首次 Update 前命中；短光束的初始化 |
| vanilla.brimstone | Brimstone | laser | 蓄力、持续与永续、反射段、来源报告为玩家 |
| vanilla.tech_x | Tech X | laser | 圆环、多目标、移动时的渲染偏移 |
| vanilla.knife | Mom's Knife | knife；接触来源由碰撞提示恢复 | 接触、投出、返回、派生刀与实体复用 |
| vanilla.bombs | Dr. Fetus、放置炸弹 | bomb；爆炸时核对 EntityRef | 爆炸前后实体是否存在、延迟与连锁爆炸 |
| vanilla.rockets | Epic Fetus | 待查标记、落点与爆炸来源 | 多阶段归属、范围与重复结算 |
| vanilla.bone | The Forgotten 骨棒 | 待查近战与投掷来源 | 挥击、蓄力投掷、返回与派生弹 |
| vanilla.sword | Spirit Sword | 待查斩击与剑气来源 | 接触、蓄力、剑气分别计数 |
| vanilla.axe | Notched Axe | 待查挥击来源 | 近战目标、挥击次数与耐久 |
| vanilla.soul_flame | Urn of Souls | 待查火焰与持续伤害来源 | 发射与持续命中分开计时，停止使用后的残留 |
| vanilla.whip | Tainted Lilith / Gello 鞭击 | 待查鞭击与子攻击来源 | 鞭击、胎儿射击、收回时的归属 |
| vanilla.familiar_shot | Incubus 等熟悉物发射的攻击 | 对应实体路径，归属由 Context 解析 | 玩家与熟悉物同时发射、不同熟悉物的批次 |
| vanilla.contact | 玩家/熟悉物接触、苍蝇、蜘蛛 | 无统一接触伤害入口 | 是否应触发道具、伤害频率、真实拥有者 |
| vanilla.persistent | 地面液体、火焰、毒与灼烧 | 无统一持续伤害入口 | 施加状态与每跳伤害、宿主消失后归属 |
| vanilla.effect_hit | 主动道具、场景效果、反弹弹幕 | 按实际实体与 DamageFlag 查证 | 效果实体与伤害实体是否相同，是否进入攻击分发 |

类别依据：[WeaponType](https://wofsauge.github.io/IsaacDocs/rep/enums/WeaponType.html)。
具体组合还需交叉检查多发、分裂、弹跳、追踪、穿透、爆炸、蓄力和武器替换。
同一武器既有近战又有远程阶段时，分别登记结果。

当前 [Context](../mod/framework/context.lua) 识别 tear、laser、knife、bomb；
DAMAGE_LASER 可将伤害归为 laser，普通玩家来源则需要额外的来源恢复。
ctx.weaponType 是框架填写的粗分类，区分上述武器时还要检查实际实体、Variant 和回调。
记录来源时使用 EntityRef 的 Type/Variant/SpawnerType、Entity、DamageFlag 及逻辑帧号。
字段含义见 [DamageFlag](https://cuerzor.github.io/IsaacDocs/rep/enums/DamageFlag.html)、
[伤害回调](https://cuerzor.github.io/IsaacDocs/rep/enums/ModCallbacks.html#mc_entity_take_dmg)。

## 3. 模组攻击与效果登记

登记键采用“模块 ID.攻击名称”，仅用于文档与测试定位。
代码仍使用现有 ctx、GetData 和伤害通道；登记一个键不会自动增加框架能力。

### 当前登记

| 登记键 | 作用 | 来源与触发 | 伤害或状态 | 组合检查 |
|---|---|---|---|---|
| crude_salt.mark | 原攻击的方向标记效果 | tear 在生成时投概率；laser/knife 每次有效命中投概率 | 同一目标刷新方向，不叠层 | 多发、持续武器、与 Trinity 同目标挂印 |
| crude_salt.shatter | 标记反向后触发的伤害与盐像 | 保存的持有者；EntityRef(owner)；默认伤害通道 | Boss 按面板伤害计算；普通敌人冻结后提交致命伤害 | 玩家来源的再次分发、默认通道竞争、死亡替换与清理 |
| trinity.aspects | 原攻击的位格与补伤害 | tear/laser/knife；EntityRef(player)；trinity:攻击哈希通道 | 基于命中 amount 补差额；激光子段共用根哈希 | 多发位格、子段去重、原有属性与其他命中效果 |
| trinity.judgment | 双印记触发的范围伤害 | Spirit 命中；沿用该攻击通道与玩家来源 | 主目标补伤害；其他目标 AOE；清除主目标印记 | 主目标排除、同帧多个审判、二次触发、目标先死亡 |
| forbidden_fruit.damage | 影响攻击数值的属性效果 | 成交后通过 CACHE_DAMAGE 更新玩家伤害 | 按品质降低本层伤害，换层恢复 | 面板计算与命中 amount 的区别、延迟攻击是否取快照 |

实现与数值：[粗盐](crude_salt_assets.md)、[三位一体](trinity_design.md)、
[禁果](forbidden_fruit_design.md)。

当前粗盐与 Trinity 接入 tear/laser/knife，bomb 保持原行为；表中其余原版路径按具体场景补查。
Trinity 补伤害和粗盐碎裂均以玩家为来源，设计上不再次触发武器命中效果。
验收时同时检查普通玩家来源和妈刀碰撞提示恢复，覆盖同帧及下一帧。

粗盐目前省略 channel，使用默认目标锁；Trinity 使用显式攻击通道。
框架已有两类锁并存的离线断言，完整模块同时触发的结果在组合测试中记录。

### 新增条目模板

新增或改变攻击形态时，在上表追加一行，并在所属模块文档填入：

```text
登记键：<module_id>.<attack_name>
实现位置：模块文件与入口函数
攻击实体：Type / Variant；根攻击与子实体的关联方式
拥有者：由哪个 ctx 或业务记录提供
触发单位：每次发射 / 每个实体 / 每次命中 / 每 N 帧
伤害基准：当前面板 / 发射时快照 / 命中 amount / 固定值
效果继承：哪些原版属性和模组效果参与，子攻击如何继承
附带伤害：来源、channel、是否再次触发命中效果
结束条件：到期、宿主消失、失去道具、换房或新局
适配决定与验证：原版路径、模组组合、测试及实机记录
```

例如新建 example_relic.wave（示例，尚未实现），若以效果实体绘制冲击波并用玩家来源结算，
需要明确粗盐能否挂方向标记、Trinity 是否分配位格。若决定接入，先设计对应的公共攻击入口；
若决定只造成独立伤害，则记录为保持原行为。视觉实体的存在本身不等于进入 onAttackHit。

## 4. 组合检查

每增加一种攻击，补“新攻击 × 已有命中效果”；每增加一种效果，补“已有攻击 × 新效果”。
两项都会产生子攻击或补伤害时，分别检查两个触发方向，并增加三项同时持有的场景。

| 组合 | 预期与观察点 | 当前证据 |
|---|---|---|
| 同一 tear/laser/knife 同时触发粗盐与 Trinity | 两份标记各自更新，通道不互相吞伤害；核对双方染色覆盖 | 单模块与通道离线测试；联合实测待补 |
| trinity.judgment → crude_salt.mark / trinity.aspects | 玩家来源补伤害不再次挂印或推进位格；覆盖主目标和 AOE | 玩家来源与妈刀提示消费有离线断言；完整链路待补 |
| crude_salt.shatter → trinity 标记目标 | 盐像替换后及时清理旧目标图标；死亡与房间清除正常 | 各模块有清理测试；联合实测待补 |
| forbidden_fruit.damage → crude_salt.shatter | Boss 伤害使用触发时面板；换层后恢复 | 单模块测试；联合实测待补 |
| forbidden_fruit.damage → trinity 补伤害/审判 | 在进入回调的 amount 上计算，不再重复乘一次禁果倍率 | 单模块测试；联合实测待补 |
| 新攻击 → 新攻击 | 子攻击继承、计数、附带伤害和结束条件与双方设计一致 | 新增时填写 |

每个选中的组合至少检查：

- **触发与归属**：首帧、重复命中、熟悉物发射、来源实体消失。
- **结算**：同帧多发、多目标、持续伤害、子段/范围伤害、下一帧再次回调。
- **状态**：获得与失去道具、普通敌人与 Boss、死亡替换、换房和保存继续。
- **表现**：颜色与 flags 的保留、大小变化、渲染偏移、动画及音效结束。

## 5. 记录与维护

模块测试覆盖确定的规则，实机验证回调时序与最终表现。
现有入口：[test_framework](../tests/test_framework.lua)、
[test_trinity](../tests/test_trinity.lua)、[test_crude_salt](../tests/test_crude_salt.lua)、
[test_forbidden_fruit](../tests/test_forbidden_fruit.lua)。

将下面的表格放在所属模块的兼容小节中；每行是一组可复现的场景：

| 攻击/组合 | 适配决定 | 预期 | 验证结果 | 证据 |
|---|---|---|---|---|
| 示例：vanilla.tech_x × 新效果 | 待定 | 写明触发频率与附带伤害 | 未测 | 测试文件/断言；游戏版本、提交、种子、操作与结果 |

攻击来源、触发单位、伤害通道、实体替换或清理行为改变时，更新登记行并重跑受影响组合。
新发现的原版路径也追加到第 2 节；已知问题记录复现步骤和 Issue 链接。
本页按 2026-10-09 的源码与离线测试整理，表中联合实测仍待执行。
