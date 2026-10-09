# Penitent Relics 架构与模块边界

项目采用模块化结构组织道具与玩法，目标游戏为 Repentance+。
工程约定见 [AGENTS.md](../../AGENTS.md)，
实际接口见 [framework_api.md](framework_api.md)。

## 1. 分层与依赖

| 层 | 职责 | 职责边界 |
|---|---|---|
| `mod/main.lua` | 环境检查、RegisterMod、初始化 Manager | 道具规则放 modules |
| `mod/framework/` | 生命周期分发、配置读取、攻击归属、标记、附带伤害 | 专有业务放所属模块 |
| `mod/modules/<id>/` | 模块规则、状态、表现与清理 | 跨模块协作走公开接口 |
| `mod/content/` | 道具、道具池、图鉴和实体声明 | 状态机放 Lua 模块 |
| `mod/resources/` | 引擎加载的图像和动画 | 源稿放 tools/assets |
| `tests/`、`tools/`、`docs/` | 验证、制作、部署、开发知识 | 留在开发仓库 |

调用方向：引擎 → hooks → Manager → 模块；模块通过 Manager 的公开接口使用公共能力。
资源物理上位于引擎要求的目录，逻辑上仍归所属模块维护，以模块 ID 命名。
`历史/` 不参与加载、测试扫描或部署。

## 2. 一个模块怎样拆分

先用一个 `init.lua`，把“触发判定、状态变更、表现、清理”写成职责明确的函数。
仅在复杂度实际增长时，在自己的目录拆出 `rules.lua`、`state.lua`、`visuals.lua`；
这些是可选私有文件，不是框架自动发现的文件。

- `init.lua` 返回唯一模块表；Manager 注入 `manager`。
- 私有文件优先返回无副作用的函数表，通过参数传入配置、状态或上下文。
- `include` 每次执行文件，不缓存。私有 helper 在初始化阶段加载一次；
  不在逐帧回调中重复 include，不再次 include Manager 来获得“共享实例”。
- 每份状态明确创建者、更新者和清理者；视觉与交易、伤害、概率分别处理。
- 一件道具通常是一个模块；不要按每个回调拆成独立玩法模块。

`include` 的缓存区别见 [IsaacDocs](https://cuerzor.github.io/IsaacDocs/rep/tutorials/Using-Additional-Lua-Files.html)。

## 3. 何时扩展框架

一个模块缺少回调时，使用 `manager:addCallback` 注册模块专用回调。
第二个模块需要同一能力时，再设计最小公共接口，更新所有调用方、测试和文档。
公共接口围绕已出现的共享需求设计。

接口变更需要先说明参数、返回值、启用条件、错误与清理责任，再实现。
需要执行顺序的规则使用明确接口；现有回调顺序见框架参考。

## 4. 状态按生命周期归属

| 状态 | 放置位置 | 生命周期 |
|---|---|---|
| 某实体的临时状态 | `GetData().pr_<id>_<name>` | 重复触发、到期、死亡、实体替换 |
| 跨帧跟踪的实体 | 模块私有记录中的 `EntityPtr` | 每次重新判空、Exists、类型、死亡 |
| 房间内列表/计时器 | 模块私有表 | 换房间清理、新游戏重置 |
| 本局规则数据 | 模块私有表或玩家 GetData | 新局与继续游戏分别处理 |
| 需要保存继续的数据 | 经明确存档协议序列化的纯数据 | 版本迁移、损坏输入、载入时恢复 |

`GetPtrHash` 是运行期索引，不是存档 ID；`EntityPtr` 和 userdata 不可作为持久化数据。
实体替换时先验证业务标识能否关联前后实体，再选择 InitSeed 等索引。

当前没有公共存档管理器。Forbidden Fruit 的 `saveState/restoreState` 是现有存档写入者，
使用 FF3 格式并兼容 FF2。它直接写 `manager.mod:SaveData`；
**第二个需要存档的模块不可另行写入并覆盖同一数据**。
届时才按公共接口变更流程引入按模块命名空间保存的总表及旧格式迁移。
存档 API 参见 [ModReference](https://cuerzor.github.io/IsaacDocs/rep/ModReference.html#savedata)。

## 5. 配置与禁用边界

静态配置、缓存和额外回调责任见 [框架参考](framework_api.md#6-静态配置与额外回调)。
禁用不删除 XML 道具、道具池或现有实体，onRegister 仍执行。
现有 setEnabled 没有资源清理协议，不应作为玩家可用的热切换功能。

模块接入见 [教程](module_guide.md)，跨攻击与效果协作见 [兼容清单](attack_compatibility.md)。
完整文档入口见 [目录](../README.md)。
