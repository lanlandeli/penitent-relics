# 框架接口参考

对应实现：[Manager](../../mod/framework/manager.lua)、
[Hooks](../../mod/framework/hooks.lua)、[Context](../../mod/framework/context.lua)、
[Config](../../mod/framework/config.lua) 和 [Util](../../mod/framework/util.lua)。
用法见 [模块教程](module_guide.md)，武器与效果组合见 [攻击兼容](attack_compatibility.md)。

## 1. 模块加载

`manifest.lua` 返回模块 ID 数组；加载路径是 `modules.<id>.init`。
模块必须返回表，填写 `id/name/version`，可选 `description/category/config/customVariantName`。
`id` 与清单一致；加载器目前会按清单赋值。
`name/version/category` 不会被加载器完整校验。

加载器注入 `module.manager`，解析可选变体，计算启用状态，再调用
`module:onRegister(manager)`。该方法在正常初始化中调用一次，禁用模块也会调用。
加载文件失败会跳过该模块；onRegister 的 Lua 错误会记录，但不会自动禁用模块。
ID 解析失败时，模块应在后续入口早返回。

`safeCall` 用 pcall 捕获 Lua 错误；已产生的状态和资源由模块负责清理。

## 2. 生命周期

模块方法中的 `self` 是模块表，不是游戏 mod 对象。
下表业务参数不包含原生回调首个 mod 参数；Hooks 已接收并去掉该参数。

| 模块方法 | 业务参数 | 原生入口 | 返回处理 |
|---|---|---|---|
| onGameStart | continued | MC_POST_GAME_STARTED | 忽略 |
| onNewRoom | 无 | MC_POST_NEW_ROOM | 忽略 |
| onUpdate | 无 | MC_POST_UPDATE | 忽略 |
| onRender | 无 | MC_POST_RENDER | 忽略 |
| onPlayerUpdate | player | MC_POST_PEFFECT_UPDATE | 忽略 |
| onEvaluateCache | player, cacheFlag | MC_EVALUATE_CACHE | 忽略 |
| onUseItem | itemId, rng, player, useFlags, activeSlot, customVarData | MC_USE_ITEM | 最后一个非 nil 值 |
| onNpcInit | npc | MC_POST_NPC_INIT | 忽略 |
| onNpcUpdate | npc | MC_PRE_NPC_UPDATE | 最后一个非 nil 值 |
| onPlayerCollide | player, collider, low | MC_PRE_PLAYER_COLLISION | 最后一个非 nil 值 |
| onNpcCollide | npc, collider, low | MC_PRE_NPC_COLLISION | 最后一个非 nil 值 |
| onFireTear | tear, ctx | MC_POST_FIRE_TEAR | 忽略 |
| onTearInit | tear, ctx | MC_POST_TEAR_INIT | 忽略 |
| onTearUpdate | tear, ctx | MC_POST_TEAR_UPDATE | 忽略 |
| onTearRender | tear, offset, ctx | MC_POST_TEAR_RENDER | 忽略 |
| onTearCollide | tear, collider, low, ctx | MC_PRE_TEAR_COLLISION | 最后一个非 nil 值 |
| onAttackHit | target, amount, dmgFlags, source, countdownFrames, ctx | MC_ENTITY_TAKE_DMG | 忽略；Hooks 不阻断原伤害 |
| onTearHit | tear, target, amount, dmgFlags, source, ctx | 同一伤害事件中的泪弹子事件 | 忽略 |
| onLaserInit / onLaserUpdate | laser, ctx | MC_POST_LASER_INIT / UPDATE | 忽略 |
| onLaserRender | laser, offset, ctx | MC_POST_LASER_RENDER | 忽略 |
| onBombInit / onBombUpdate | bomb, ctx | MC_POST_BOMB_INIT / UPDATE | 忽略 |
| onBombRender | bomb, offset, ctx | MC_POST_BOMB_RENDER | 忽略 |
| onKnifeInit / onKnifeUpdate | knife, ctx | MC_POST_KNIFE_INIT / UPDATE | 忽略 |
| onKnifeRender | knife, offset, ctx | MC_POST_KNIFE_RENDER | 忽略 |

- 只有 `onUseItem` 按 manifest 顺序构建分发表；其他事件由 `pairs` 构建，顺序不保证。
- 有返回值的模块事件仍会继续调用后面的模块。
- 默认返回 nil。碰撞回调的 true/false 按对应 API 的语义使用。
- onNpcUpdate 对应 **PRE** 更新；true 请求跳过原生 AI。
- onUseItem 的布尔值控制使用动画；需要明确充能、移除、动画行为时返回
  `{ Discharge = ..., Remove = ..., ShowAnim = ... }`，只观察别的道具时返回 nil。
- 玩家、NPC、碰撞及属性回调不会自动过滤道具持有。
- 攻击实体生命周期只在框架解析到玩家归属时分发；初始化过早可能被跳过。
- onAttackHit 是伤害应用前的通知，不是确认扣血、击杀或掉落的通知。
  同一次泪弹伤害还会触发 onTearHit，不要在两处重复结算同一规则。
- 攻击分发处理 Context 已识别的来源，其他伤害路径见兼容清单。
- Render 只绘制，不推进规则、计时、概率或交易；更新与渲染频率不能视为相同。

引擎语义来源：[ModCallbacks](https://cuerzor.github.io/IsaacDocs/rep/enums/ModCallbacks.html)。

## 3. 攻击上下文字段

| 字段 | 攻击实体生命周期 | 普通 onAttackHit 伤害上下文 |
|---|---|---|
| type | tear / laser / knife / bomb | 同左，激光伤害标志可修正分类 |
| player | 解析到的玩家 | 可能为 nil |
| isPlayerOwned | 分发前要求为真 | 可能仅由来源类型推断为真 |
| entity | 当前攻击实体 | 可能为 nil |
| variant | 实体 Variant | 来源 Variant |
| weaponType | 粗粒度武器枚举 | 未填充 |
| isSpecial | 仅等于 Variant ~= 0 | 未填充 |
| tear / laser / knife / bomb | 对应的一个别名 | 未填充 |
| source / sourceType | 通常无 | 原始 EntityRef 与来源类型 |

妈刀恢复路径可返回额外的刀上下文字段，模块按实际来源读取。
`weaponType` 不区分科技、科技 X 与硫磺火；`isSpecial` 不是道具协同分类。
需要区分时检查已验证有效的实体类型/属性，并查证 API。

模块优先消费 ctx；熟悉物归属由框架处理。
`findPlayerWithCollectible` 只寻找持有者，不证明那次攻击的来源。
缺少可信归属时，按模块设计跳过效果或使用明确的有限兜底。

妈刀同帧碰撞提示由框架维护，用 EntityPtr 保存刀；恢复时先消费提示，再分发伤害。
模块使用恢复后的 ctx。

## 4. 公开工具

| 接口 | 实际行为与注意点 |
|---|---|
| getConfig(module, key, fallback) | 全局覆盖 > 模块默认 > fallback；仅 nil 使用 fallback，保留 false/0 |
| isEnabled(id) | 查询分发启用状态 |
| setMark(moduleId, entity) / hasMark(...) | 框架内部键为 penitentrelics_<id>；只通过接口访问 |
| findPlayerWithCollectible(itemId) | 找到第一个持有者，找不到返回 nil |
| anyPlayerHasCollectible(itemId) | 布尔持有判断，不提供来源证明 |
| dealDamage(target, amount, flags, source[, channel]) | 见下节 |
| addCallback(callbackId, fn[, filter]) | 直接注册额外回调；不自动包装安全调用/启用检查 |
| addPriorityCallback(callbackId, priority, fn[, filter]) | 额外指定原生优先级，包装责任相同 |
| Util.log(message) | 仅 debug=true 时输出 |
| Util.warn(message) | 总是输出 [PenitentRelics][WARN] |
| Util.safeCall(fn, context) | 捕获 Lua 错误并计数；只返回成功布尔值，不透传 fn 返回值 |
| Util.hsvColor(h, s, v) | h 为角度，s/v 为 0–1 |
| Util.angleToVector(angleDeg, length) | 角度为度 |
| Util.randomAngleVector(length) | 目前使用 math.random；不用于需要种子复现的玩法判定 |

`customVariantName` 的既有配套查询是
`manager.Variants:getByEffect(self.id)`。
普通自定义效果实体可在 onRegister 按名称解析。

`dispatch*`、`loadModules`、`rebuildDispatchLists` 和内部组件表属于框架实现。
模块不主动分发其他模块回调，不修改 Manager 内部状态。

## 5. 附带伤害的边界

调用前检查目标与数值，提供伤害来源。
去重键是“当前逻辑帧 + 目标 GetPtrHash + channel”；省略 channel 则共用目标级旧锁。
同一模块/攻击使用稳定通道。

返回 true 表示已调用 TakeDamage；目标不存在或同帧通道已锁时返回 false。
最终扣血由引擎结算。模块负责来源选择和跨帧重入，组合场景见攻击兼容清单。
代码在提交前写锁，某次伤害被引擎拒绝时该通道也不会在同帧重试。

## 6. 静态配置与额外回调

默认配置是只读表，全局覆盖按模块 ID 浅合并，首次读取后缓存。
嵌套表不会递归合并；不原地修改读出的表。配置修改后完整重启游戏验证。
`enabled` 只读取全局 `modules.<id>.enabled`，未设置时默认开启；
不要用 `module.config.enabled` 作为禁用开关。

额外回调必须在 onRegister 注册，接收首个 mod 参数，自行检查启用状态并 safeCall。
有返回值时用局部变量接收业务结果；不能直接 return safeCall 的成功布尔值。
框架目前没有 onNewLevel、onGameExit、通用 pickup 或 effect 生命周期；
使用这些事件时按模块教程显式注册额外回调。
