# 开发文档

新道具从 [模块教程](module_guide.md) 开始；涉及攻击时，同时填写
[攻击兼容清单](attack_compatibility.md)。提交与部署按 [工作流](agent_workflow.md) 执行。

## 通用文档

| 文档 | 内容 |
|---|---|
| [开发规范](../AGENTS.md) | 仓库边界、协作与版本约定 |
| [模块教程](module_guide.md) | 模块、内容、配置和测试的完整接入示例 |
| [框架接口](framework_api.md) | 生命周期、ctx、公共方法及返回值 |
| [攻击兼容](attack_compatibility.md) | 原版攻击、模组攻击登记与组合检查 |
| [架构](architecture.md) | 分层、模块拆分、状态和存档归属 |
| [代码风格](code_style.md) | Lua 命名、格式、配置和日志 |
| [视觉规范](custom_visuals.md) | 实体、动画、坐标、音效和清理 |
| [美术工具](../tools/anim_workflow.md) | 编辑器、源稿和资源制作流程 |
| [开发工作流](agent_workflow.md) | 查证、验证、部署、GitHub 与交接 |
| [API 资料](api_research.md) | 资料链接与待核实事项 |

## 模块文档

| 模块 | 规则与资源 |
|---|---|
| Crude Salt | [规则与素材](crude_salt_assets.md) |
| Trinity | [设计](trinity_design.md)、[素材](trinity_assets.md) |
| Forbidden Fruit | [设计与资源](forbidden_fruit_design.md) |

新模块在此追加入口。简单模块可合写规则与素材；内容较多时再拆成 design 与 assets。
通用规则只在对应专题维护，模块文档保留玩法、实现差异和验收场景。
