# API 资料索引

查引擎 API 使用下列资料；项目接口见 [框架参考](framework_api.md)。

## 1. 查阅顺序

1. 以 [cuerzor IsaacDocs](https://cuerzor.github.io/IsaacDocs/rep/) 为项目首选 API 资料。
   该资料由社区维护。
2. 页面缺失或翻译不明确时，查 [英文上游](https://wofsauge.github.io/IsaacDocs/rep/)
   和游戏随附脚本/资源，记录使用的游戏版本与 API 来源。
3. 框架行为查当前源码与测试；工程约定查 AGENTS。
4. 模块设计描述玩法；实机验证记录游戏版本、操作与结果。

## 2. 资料入口

| 主题与来源 | 采用的事实 / 文档落点 |
|---|---|
| [ModCallbacks](https://cuerzor.github.io/IsaacDocs/rep/enums/ModCallbacks.html) | 回调签名与返回值；framework_api |
| [WeaponType](https://wofsauge.github.io/IsaacDocs/rep/enums/WeaponType.html) | 原版武器类别；attack_compatibility |
| [DamageFlag](https://cuerzor.github.io/IsaacDocs/rep/enums/DamageFlag.html) | 伤害标志与来源分类；attack_compatibility |
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

## 3. 使用与维护

查 API 时重点看目标版本、参数、返回值和回调过滤条件。
资料与实际表现有差异时，在对应 PR 或 Issue 中记录复现方式与结论。
接口变化同步框架参考与调用示例；确定的玩法规则写入模块文档。
