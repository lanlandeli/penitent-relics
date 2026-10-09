# 开发文档

新道具从 [模块教程](development/module_guide.md) 开始；涉及攻击时，按改动范围查阅
[攻击兼容清单](development/attack_compatibility.md)。提交与部署按 [工作流](development/agent_workflow.md) 执行。

```text
docs/
  README.md       文档入口
  development/    通用开发规范、教程与参考
  modules/        各道具的设计、素材与验收
```

## 通用开发文档

| 文档 | 内容 |
|---|---|
| [开发规范](../AGENTS.md) | 仓库边界、协作与版本约定 |
| [模块教程](development/module_guide.md) | 模块、内容、配置和测试的完整接入示例 |
| [框架接口](development/framework_api.md) | 生命周期、ctx、公共方法及返回值 |
| [攻击兼容](development/attack_compatibility.md) | 原版攻击、模组攻击登记与组合检查 |
| [架构](development/architecture.md) | 分层、模块拆分、状态和存档归属 |
| [代码风格](development/code_style.md) | Lua 命名、格式、配置和日志 |
| [视觉规范](development/custom_visuals.md) | 实体、动画、坐标、音效和清理 |
| [美术工具](../tools/anim_workflow.md) | 编辑器、源稿和资源制作流程 |
| [开发工作流](development/agent_workflow.md) | 查证、验证、部署、GitHub 与交接 |
| [API 资料](development/api_research.md) | 引擎 API 来源与查阅方法 |

## 模块文档

| 模块 | 规则与资源 |
|---|---|
| Crude Salt | [规则与素材](modules/crude_salt_assets.md) |
| Trinity | [设计](modules/trinity_design.md)、[素材](modules/trinity_assets.md) |
| Forbidden Fruit | [设计与资源](modules/forbidden_fruit_design.md) |

新模块文档放入 `modules/`，并在上表追加入口。简单模块可合写规则与素材；
内容较多时再拆成 `<module_id>_design.md` 与 `<module_id>_assets.md`。
通用规则在 development/ 维护，modules/ 记录玩法、实现差异和验收场景。
提交的验证结果与问题跟踪放在 PR 或 Issue，确定的规则再更新到文档。
