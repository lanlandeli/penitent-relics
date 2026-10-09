# Penitent Relics 架构与模块边界

项目目标是持续增加可以组合的原版风格道具。运行时采用 Repentance+ 原生 Lua API；
无法可靠表达的效果先调整设计，不取消并重放原伤害。协作约束见 [AGENTS.md](../AGENTS.md)，
实际接口见 [framework_api.md](framework_api.md)。

## 1. 分层与依赖

| 层 | 职责 | 禁止承担的职责 |
|---|---|---|
| `mod/main.lua` | 版本门禁、RegisterMod、初始化 Manager | 具体道具规则 |
| `mod/framework/` | 生命周期分发、配置读取、攻击归属、标记、附带伤害 | 按道具名称分支的业务逻辑 |
| `mod/modules/<id>/` | 模块规则、状态、表现与清理 | 调用其他玩法模块的私有实现 |
| `mod/content/` | 道具、道具池、图鉴和实体声明 | Lua 状态机 |
| `mod/resources/` | 引擎加载的图像和动画 | 源稿、截图、测试和开发脚本 |
| `tests/`、`tools/`、`docs/` | 验证、制作、部署、开发知识 | 游戏运行时依赖 |

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
- 所有权必须明确：谁创建状态，谁更新，谁清理；视觉失败不应改变交易、伤害或概率结果。
- 一件道具通常是一个模块；不要按每个回调拆成独立玩法模块。

`include` 的缓存区别见 [IsaacDocs](https://cuerzor.github.io/IsaacDocs/rep/tutorials/Using-Additional-Lua-Files.html)。

## 3. 何时扩展框架

一个模块缺少回调时，先使用 `manager:addCallback` 的受控例外。
第二个模块需要同一能力时，再设计最小公共接口，更新所有调用方、测试和文档。
不要仅为未来可能出现的需求建立事件总线、通用状态容器或继承体系。

接口变更需要先说明参数、返回值、启用条件、错误与清理责任，再实现。
模块间不得依赖回调偶然顺序；只有 `onUseItem` 当前保证 manifest 顺序。

## 4. 状态按生命周期归属

| 状态 | 放置位置 | 必须说明的边界 |
|---|---|---|
| 某实体的临时状态 | `GetData().pr_<id>_<name>` | 重复触发、到期、死亡、实体替换 |
| 跨帧跟踪的实体 | 模块私有记录中的 `EntityPtr` | 每次重新判空、Exists、类型、死亡 |
| 房间内列表/计时器 | 模块私有表 | 换房间清理、新游戏重置 |
| 本局规则数据 | 模块私有表或玩家 GetData | 新局与继续游戏分别处理 |
| 需要保存继续的数据 | 经明确存档协议序列化的纯数据 | 版本迁移、损坏输入、载入时恢复 |

`GetPtrHash` 是运行期索引，不是存档 ID；`EntityPtr` 和 userdata 不可作为持久化数据。
实体替换时仅使用已验证可关联的业务标识，不保证任意实体替换都会保留 `InitSeed`。

当前没有公共存档管理器。Forbidden Fruit 的 `saveState/restoreState` 是现有存档写入者，
使用 FF3 格式并兼容 FF2。它直接写 `manager.mod:SaveData`；
**第二个需要存档的模块不可另行写入并覆盖同一数据**。
届时才按公共接口变更流程引入按模块命名空间保存的总表及旧格式迁移。
本说明不表示该公共接口已实现。参见 [ModReference](https://cuerzor.github.io/IsaacDocs/rep/ModReference.html#savedata)。

## 5. 配置与禁用边界

静态配置、缓存和额外回调责任见 [框架参考](framework_api.md#6-静态配置与额外回调)。
禁用不删除 XML 道具、道具池或现有实体，onRegister 仍执行。
现有 setEnabled 没有资源清理协议，不应作为玩家可用的热切换功能。

## 6. 文档分工

通用规则留在 AGENTS；设计理由与分层留在本文；完整接口仅在 framework_api 维护。
接入步骤由 module_guide 维护，验证与部署由 agent_workflow 维护。
模块文档只记录该模块的规则、状态、资源与验收差异，链接通用约定，不复制整张接口表或配置。
文档入口集中在 [README](../README.md#反馈与开发)；旧方案、版本流水和单次验收记录归档。

“设计要求”“代码已实现”“离线验证通过”“游戏内验证通过”是四种不同状态。
记录版本与证据，不把历史“已交付”标记当作当前版本已经完整实测。
