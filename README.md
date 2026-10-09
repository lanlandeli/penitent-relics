# Penitent Relics · 忏悔遗物

面向《以撒的结合：忏悔+》的原版风格道具扩展。要求 Repentance+ 原生 Lua API，
不依赖 REPENTOGON。当前包含 Crude Salt、Trinity、Forbidden Fruit 三个独立玩法模块。

GitHub 开发仓库：[lanlandeli/penitent-relics](https://github.com/lanlandeli/penitent-relics)。
问题和功能规划使用 Issues，代码变更使用分支与 Pull Request；
操作步骤见 [GitHub 工作流](docs/agent_workflow.md#8-github-开发流程)。
## 安装与体验

1. 从源码使用时，先按 [验证工作流](docs/agent_workflow.md) 完成自动检查。
2. 检查 tools/deploy.bat 中 GAME_MODS；当前本机路径指向 E 盘 SteamLibrary。
3. 确认目标目录和需保留的数据后运行 `cmd /d /c tools\deploy.bat`。
   脚本只镜像 mod/，但 /MIR 会删除目标中源目录没有的文件。
4. 完全重启游戏，在 Mods 菜单启用 Penitent Relics，再开始测试局。

| 道具 | 简述 | 设计资料 |
|---|---|---|
| Crude Salt | 记录敌人移动方向，反向移动触发盐雕或 Boss 额外伤害 | [视觉与规则说明](docs/crude_salt_assets.md) |
| Trinity | 三种攻击位格轮转，印记组合触发审判 | [设计](docs/trinity_design.md)、[素材](docs/trinity_assets.md) |
| Forbidden Fruit | 每层初始房选择一件付费道具，按品质承担本层伤害降低 | [设计](docs/forbidden_fruit_design.md) |

具体数值以模块默认配置与 mod/config.lua 覆盖为准。开发开关（如禁果 grantOnNewGame）
也应在测试前检查；示例效果不等于当前全部组合已实机验收。

## 调试

在目标游戏对应的 options.ini 开启 EnableDebugConsole=1。
Windows 常见目录为“文档/My Games/Binding of Isaac Repentance+”，
实际位置以当前安装和日志为准；进入游戏后使用键盘对应的控制台键。

从 log.txt 搜索 `[PenitentRelics]` 和各道具的 `ready: giveitem c`，
复制日志里的数字运行时 ID。不要用 XML 中的 1000/1001/1002 直接调道具。
普通框架日志受 debug 开关控制，WARN 与模块的启动 DebugString 不受该开关统一控制。
发现异常先记录角色、种子、道具组合、复现步骤及相关日志。

## 开发文档导航

| 要做什么 | 入口 |
|---|---|
| 了解必须遵守的契约与完成标准 | [AGENTS.md](AGENTS.md) |
| 新建一件道具、注册内容与配置 | [模块教程](docs/module_guide.md) |
| 查询当前生命周期、ctx、工具和限制 | [框架接口](docs/framework_api.md) |
| 决定模块边界、拆分与状态归属 | [架构](docs/architecture.md) |
| 制作动画、图标和音效 | [视觉规范](docs/custom_visuals.md)、[工具流程](tools/anim_workflow.md) |
| 运行测试、部署与记录实测 | [工作流](docs/agent_workflow.md) |
| 查证引擎 API 与已知限制 | [调研记录](docs/api_research.md) |
| 保持 Lua 与文档一致风格 | [代码风格](docs/code_style.md) |

新道具不是只加一个 Lua 文件：通常还需要 manifest、items.xml、itempools.xml、
info_display.xml、图标、配置和对应测试。按教程选择实际需要的部分。

## 目录

```text
mod/
  main.lua                 唯一入口与版本门禁
  config.lua               静态全局覆盖
  framework/               公共接口与引擎桥接
  modules/<module_id>/     模块私有实现
  modules/manifest.lua     模块注册
  content/                 新内容 XML
  resources/               游戏运行时素材
tests/                     Lua 5.3 离线回归
tools/                     检查、部署与资源制作
docs/                      当前开发文档
历史/                      本地归档，不纳入 GitHub
```

## 开发环境与能力边界

本仓库离线使用 tools/lua/ 下的 Lua 5.3.6（lua53.exe、luac53.exe、lua53.dll），
保持 Lua 5.3 兼容子集。该工具目录被 Git 忽略，新检出需自行准备对应工具。
`tools/luacheck.bat` / `tools/luacheck.sh` 实际用 luac -p 检查 mod/ 语法；
全部回归测试的 PowerShell 命令集中在工作流中。

框架封装泪弹、激光、刀、炸弹及常用玩家/NPC/房间回调；
是否产生道具效果由模块检查持有与适配条件。缺失的生命周期按模块教程接入。
错误隔离、配置和归属解析各有明确边界，不能据此声称兼容所有原版道具或其他模组。
## 本地历史归档

本机的 `历史/2026-10-09/` 保存旧过程稿、工具和文档快照，附有原路径及 SHA-256 清单。
整个历史目录已被 Git 忽略，不随 GitHub 克隆或上传；需要迁移这些资料时另行复制。
GitHub 从当前版本建立新的提交历史，原来的 Git 历史仅保存在本机的
`archive/pre-github-20261009` 分支，不推送到远程。

归档文件仅供追溯，不作为当前开发规范。恢复时先比较原路径是否已有新文件；
旧工具可能带过时的输出路径，运行前应改为独立目录。
历史目录不参与游戏加载或部署。
