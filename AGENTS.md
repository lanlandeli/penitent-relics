# Penitent Relics 开发规范

本文件约定仓库的工程边界。模块接入与示例见 [模块教程](docs/development/module_guide.md)，
接口签名见 [框架参考](docs/development/framework_api.md)，执行步骤见 [开发工作流](docs/development/agent_workflow.md)。

## 1. 项目约定

目标游戏为 Repentance+，Lua 代码与离线测试采用 Lua 5.3 兼容语法。
新增引擎调用时，核对目标版本的参数、返回值和使用条件；
API 资料入口见 [api_research.md](docs/development/api_research.md)。

暂不考虑联机实现。

完整目录见 [开发文档](docs/README.md)。公共规则在专题中维护，模块文档记录自己的玩法与差异。

## 2. 目录与协作边界

```text
mod/
  main.lua                 模组入口与框架初始化
  config.lua               全局配置覆盖
  framework/               公共接口与引擎回调桥接
  modules/manifest.lua     模块清单
  modules/<module_id>/     道具或玩法的私有实现
  content/                 XML 内容注册
  resources/               游戏运行时资源
tests/                     Lua 回归测试
tools/                     检查、部署与资源制作工具
docs/
  README.md                文档目录
  development/             通用开发规范、教程与参考
  modules/                 各道具的设计、素材与验收
```

- 一件道具或独立玩法放在一个模块内，按需拆分规则、状态、表现和清理函数。
- 跨模块能力通过框架公开接口提供；多个模块需要同一能力时提取公共实现。
- manifest、全局配置和内容 XML 保持局部修改，保留现有 ID 与资源引用。
- 开始前检查未提交差异；保留其他开发者的修改，并行修改同一文件时协调范围。
- 游戏目录使用验证后的 mod/ 部署产物；源码修改在仓库完成。

## 3. 模块接入与回调

模块在 mod/modules/<id>/init.lua 返回表，并加入 manifest。
id 与目录一致，name 为英文名，version 使用 MAJOR.MINOR.PATCH；
默认参数放 config，manager 由框架注入。完整示例见模块教程。

优先实现框架生命周期；模块自行检查道具持有、实体类型和事件过滤条件。
回调默认返回 nil；需要改变原生行为时，按对应 API 的返回契约处理。
主动道具先比较 itemId；碰撞回调中 nil、true、false 分别按引擎定义使用。

额外回调在 onRegister 中通过 Manager 注册，接收首个 mod 参数，
检查模块启用状态并包装 safeCall；业务返回值单独保存和返回。
模块消费 ctx 提供的攻击来源，缺少字段时按玩法设计跳过或使用明确兜底。
详细字段、顺序、禁用和错误处理语义以框架参考为准。

## 4. 状态、实体与伤害

- 实体状态使用 GetData().pr_<module_id>_<name>；清理仅处理本模块的数据。
- 运行期表索引用 GetPtrHash；跨帧引用用 EntityPtr，读取时检查 Ref、Exists、类型和存活状态。
- 实体替换使用经验证的业务标识关联；保存继续只序列化纯数据，记录格式版本和恢复方式。
- 每份状态说明创建、刷新、结束和重建时机；清理函数可重复执行。
- 附带伤害调用 manager:dealDamage，使用稳定的模块/攻击通道，并处理重入。
  原始命中的伤害、死亡和掉落交给引擎结算。
- 伤害前回调是命中通知；击杀、交易成功等结果使用对应生命周期或明确的状态证据确认。
- 规则更新与视觉更新分开，渲染只绘制；玩法概率使用可复现的 RNG。

持久化由模组共用一个 SaveData 槽。当前写入者是 Forbidden Fruit；
新增存档模块时先按架构文档建立公共命名空间与旧格式迁移。

## 5. 配置、内容与资源

- 默认配置由模块维护，项目覆盖放 mod/config.lua，读取用 cfg/getConfig。
  新配置说明单位、有效范围和叠加规则。
- 模块保持私有状态，框架能力通过公开方法调用。
- 游戏文本、代码/资源注释和日志使用英文；开发文档可使用中文。
- 新内容先检查名称与本地 ID 占用，运行时 ID 按名称解析。
- PNG 使用 RGBA，图集与 ANM2 路径大小写一致；资源以模块 ID 表达归属。
- 自定义场景特效注册中性效果变体，动画、坐标与生命周期按视觉规范实现。
- Lua 使用 4 空格；函数与字段 lowerCamelCase，局部常量 UPPER_SNAKE_CASE。
  详细格式和语言规则集中在 code_style.md。

## 6. 验证与交接

按 [工作流第 5 节](docs/development/agent_workflow.md#5-自动验证在仓库根目录运行) 执行 Lua 语法、
全部 tests/test_*.lua 和差异检查；资源修改追加 XML/ANM2、图片与引用检查。

攻击相关变更更新 [兼容清单](docs/development/attack_compatibility.md)，登记新攻击并检查受影响的组合。
包含状态、概率、伤害、实体替换、主动道具返回值或碰撞语义的模块增加对应回归测试。
覆盖未触发、正常触发、重复触发、失效与清理；Boss 差异和公共接口变更按实际功能补充。
Mock 体现关键 API 语义，用断言验证可观察结果。

自动检查通过后可部署本地测试，实机验证涉及的引擎行为。
交接记录改动、验证结果、部署状态和未覆盖项；格式见工作流，按任务填写适用内容。

## 7. 接口与版本维护

生命周期参数、ctx 字段、公共方法、配置语义、状态键和资源路径变化时：

1. 说明接口变化及兼容方式。
2. 更新全部调用方、回归测试和对应文档。
3. 按影响更新版本：修复 PATCH，兼容的新能力 MINOR，破坏性接口变更 MAJOR。

仅修改文档、注释或测试时保持模组版本。
