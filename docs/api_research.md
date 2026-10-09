# API 资料索引与待验证事项

核对日期：2026-10-09。范围：Repentance+ 原生 Lua、当前仓库框架和开发流程。
查证记录不构成当前构建的实机验收；接口细节集中在 [框架参考](framework_api.md)。

## 1. 证据层次

1. 以 [cuerzor IsaacDocs](https://cuerzor.github.io/IsaacDocs/rep/) 为项目首选 API 资料。
   首页明确说明这是社区维护文档；不要称为游戏官方规范。
2. 页面缺失或翻译不明确时，查 [英文上游](https://wofsauge.github.io/IsaacDocs/rep/)
   和游戏随附脚本/资源。只采用目标版本提供的原生 API，不混入扩展器接口。
3. 框架行为由当前源码与测试核对；项目限制由 AGENTS 规定。
4. 模块设计描述预期行为；实机结论必须有游戏版本、操作及结果记录。

公开资料不能替代版本核对，也不能让项目约定变成“引擎保证”。

## 2. 资料入口

| 主题与来源 | 采用的事实 / 文档落点 |
|---|---|
| [ModCallbacks](https://cuerzor.github.io/IsaacDocs/rep/enums/ModCallbacks.html) | 区分各回调签名、缓存/使用/伤害/碰撞返回语义；framework_api |
| [ModReference](https://cuerzor.github.io/IsaacDocs/rep/ModReference.html) | 原生回调注册、优先级及按 mod 保存字符串；architecture |
| [额外 Lua 文件](https://cuerzor.github.io/IsaacDocs/rep/tutorials/Using-Additional-Lua-Files.html) | include 不缓存，避免重复初始化有状态模块；architecture |
| [代码实践](https://wofsauge.github.io/IsaacDocs/rep/tutorials/GoodPractices.html) | 小函数与清晰职责优先，避免无证据的微优化；code_style |
| [items.xml](https://cuerzor.github.io/IsaacDocs/rep/xml/items.html) | content 增量物品、resources 替换，以及 gfx/cache 字段；module_guide |
| [entities2.xml](https://cuerzor.github.io/IsaacDocs/rep/xml/entities2.html) | variant 可留空分配、anm2root 相对路径；custom_visuals |
| [EntityPtr](https://wofsauge.github.io/IsaacDocs/rep/EntityPtr.html) | 实体失效时 Ref 可变 nil；状态与清理约束 |
| [Entity.SetColor](https://cuerzor.github.io/IsaacDocs/rep/Entity.html#setcolor) | 第二参 Duration，不是淡入时长；custom_visuals |
| [Sprite](https://cuerzor.github.io/IsaacDocs/rep/Sprite.html) | Play/Update/SetFrame 与独立动画推进；custom_visuals |
| [SFXManager.Play](https://cuerzor.github.io/IsaacDocs/rep/SFXManager.html#play) | FrameDelay 为重播间隔；custom_visuals |
| [RNG](https://cuerzor.github.io/IsaacDocs/rep/RNG.html) | 显式种子与随机序列管理；module_guide |
| [EntityPlayer](https://cuerzor.github.io/IsaacDocs/rep/EntityPlayer.html) | GetCollectibleRNG、AddCacheFlags/EvaluateItems；module_guide |

没有采纳其他模组教程中的固定“安全 ID 区间”、扩展器回调或未查证通用兼容保证。

## 3. 待验证与维护事项

- 未查到公开且完整的 info_display.xml schema；当前格式来自仓库现有内容。
  新条目必须在目标 Repentance+ 内置图鉴中确认。
- entities2 文档对部分目录行为标注未测试；仓库自定义效果布局不能据此声称覆盖所有版本。
- 原版实体替换是否保留种子、特定激光的 offset、存档路径与热重载效果需目标构建验证。
- 当前框架没有统一保存接口、模块卸载清理、注册失败自动禁用或所有事件的稳定排序。
- Forbidden Fruit 的额外退出回调没有按当前要求完整使用 safeCall，额外回调的 enabled
  检查也应逐项审查，修复需覆盖退出与禁用状态的回归。
- tools/process_forbidden_fruit_assets.py 会生成历史藤蔓等素材；
  它不是全套现行美术的可靠一键重建入口，运行前应检查输出并在隔离目录比较。

以上事项应在对应开发任务中验证并更新结论；已完成项移入历史记录。

## 4. 维护方式

新增或变更 API 时记录“链接 + 游戏版本 + 返回/过滤语义 + 本项目使用方式 + 验证状态”。
接口实现变化先更新 framework_api 和根契约，再改教程与受影响模块文档；
不要在多个教程复制完整接口表。设计中的验收清单与已执行记录分别标注。
