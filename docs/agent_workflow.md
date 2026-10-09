# 开发、验证与部署工作流

先读 [AGENTS.md](../AGENTS.md)。此文档给出执行顺序，接口语义只在
[framework_api.md](framework_api.md) 维护，视觉细则见 [custom_visuals.md](custom_visuals.md)。

## 1. 修改前：契约、现场、搜索

从仓库根目录执行：

```powershell
git status --short
git diff --stat
rg --files mod tests docs tools
rg -n "目标函数|配置名|资源名" mod tests docs
git diff -- 计划修改的文件
```

检查未跟踪文件也可能是正在开发的成果，不能按“未提交”判为废弃。
先写明目标、涉及文件、不变量和完成依据，再选择最小实现。
不要为这一步清理其他人的修改；并行工作只在任务明确要求时划分互不重叠的文件。

## 2. 查证与适用范围

修改引擎交互前查 [项目资料索引](api_research.md) 和对应 IsaacDocs 页面，记录：
目标游戏版本、类/方法或回调、完整参数、过滤参数、返回规则、Bug/Note。
IsaacDocs 是社区维护资料，不是无条件的引擎行为保证。
中文页缺失时查看英文上游或游戏随附资料；有冲突时记录最小复现场景。

不要为纯文档排版、归档或不涉及 API 的改动凭空加入武器/视觉验收。
文档技术纠错仍要查源码与相关 API；无法查证的描述应标为待验证。

## 3. 实现前的行为矩阵

根据任务使用需要的行，其余标“不适用”：

| 范围 | 需要决定 | 最低验证 |
|---|---|---|
| 属性 | 持有份数、加法/乘法、相关 CacheFlag | 获得、移除、重复重算、状态恢复 |
| 主动道具 | 充能、槽位、useFlags、重复使用 | 自己/其他道具、返回值及失败路径 |
| 敌人/房间 | Boss 差异、刷新与实体替换 | 重复触发、失效、死亡、换房、新局 |
| 保存继续 | 保存哪些纯数据、版本迁移 | 新局、继续、损坏或旧版本数据 |
| 视觉/音效 | 坐标、时长、层级、结束条件 | 完整周期、原尺寸、非零 offset、清理 |

攻击任务补充：

| 攻击路径 | 明确选择支持/排除/复用原版 | 关注点 |
|---|---|---|
| 普通泪弹 | 按本模块设计填写 | Init/Fire 幂等、概率与原生方向动画 |
| 科技 | 同上 | 首次 Update 前可能已命中，ctx 缺字段 |
| 科技 X | 同上 | 圆形中心、移动时 RenderOffset |
| 硫磺火 | 同上 | 子段、同轮多束、持续与永续、触发间隔 |
| 妈刀及派生攻击 | 同上 | 接触来源恢复、返回段、同帧提示消费 |
| 炸弹 | 同上 | 爆炸来源是否可恢复，排除时不产生效果 |
| 熟悉物 | 同上 | 通过 ctx 解析归属，不复制追溯逻辑 |
| 多模块/同帧多发攻击 | 同上 | 各自命名空间、伤害通道与递归边界 |

## 4. 最小实现

仅使用当前公开接口；一个道具专用逻辑留在模块私有目录。
优先早返回与幂等状态变更；将规则、表现与清理分开。
共享接口变更按 AGENTS 的迁移流程处理。不得以视觉错误触发重试交易或重复伤害。

## 5. 自动验证：在仓库根目录运行

Windows 本地使用 Lua 5.3.6，将 lua53.exe、luac53.exe 和 lua53.dll 放入 tools/lua/。
该工具目录不纳入 Git，新克隆需自行准备；GitHub Actions 会安装 Lua 5.3。

以下 PowerShell 会发现全部 test_*.lua，避免清单漏掉新增测试。
任何命令失败就停止，不继续部署。

```powershell
$ErrorActionPreference = "Stop"
cmd /d /c tools\luacheck.bat
if ($LASTEXITCODE -ne 0) { throw "Lua syntax check failed" }

$tests = @(Get-ChildItem -LiteralPath tests -Filter "test_*.lua" -File |
    Sort-Object Name)
if ($tests.Count -eq 0) { throw "No regression tests found" }
foreach ($test in $tests) {
    & .\tools\lua\lua53.exe $test.FullName
    if ($LASTEXITCODE -ne 0) { throw "Failed: $($test.Name)" }
}

git diff --check
if ($LASTEXITCODE -ne 0) { throw "Whitespace check failed" }
```

当前包含 test_main、test_framework、test_crude_salt、test_trinity、test_forbidden_fruit。
`luacheck.bat` 实际运行 luac -p，只检查语法，不是完整静态分析；
Lua 5.3 测试也不提供真实 Isaac 引擎。

修改 XML/ANM2 或文档内资源样例时，追加检查：

```powershell
$files = Get-ChildItem -LiteralPath mod -Recurse -File |
    Where-Object { $_.Extension -in ".xml", ".anm2" }
foreach ($file in $files) {
    $null = [xml](Get-Content -LiteralPath $file.FullName -Raw)
}
```

XML 解析只证明格式合法，还需核对 ID 占用、资源存在、大小写、动画名及 PNG 尺寸/RGBA。
文档任务另检查相对链接、Lua 示例语法、路径与实际调用方。
Mock 只覆盖实现需要的 API；空桩不证明价格、碰撞或引擎生命周期正确。

## 6. 本地测试部署与实机验收

顺序是：自动验证通过 → 部署当前 mod/ → 重启游戏 → 实机场景 → 记录结果。
这解决“尚未部署却要求已完成当前版本实测”的循环。
缺少实测的构建可以用于本地验证，但不能被描述为已经完整验收的发布版本。

部署前：

- 检查 tools/deploy.bat 中 GAME_MODS 与 TARGET，确认目标是 PenitentRelics。
- 脚本使用 robocopy /MIR，会移除目标中源目录没有的文件。
  先检查并备份目标内需保留的存档或手工资料；实际存档位置按目标游戏确认。
- 只镜像 mod/；源稿、工具、测试、文档和历史目录都不部署。

```powershell
cmd /d /c tools\deploy.bat
if ($LASTEXITCODE -ne 0) { throw "Deployment failed" }
```

脚本内部将 robocopy 0–7 视为成功。仍须检查输出和源/目标文件：
不要只看到版本号相同就认为所有图片与 XML 都已刷新。
至少核对 main.lua、修改过的模块、XML 和素材的 SHA-256；条件允许时比较完整 mod/ 文件列表。
完全重启游戏后记录实际构建、模组版本、角色/种子、道具组合、操作与观察结果。

按任务实测获得/移除、普通敌人/Boss、连续触发、换房、新局、保存继续及武器矩阵。
视觉追加完整播放、层级、非零偏移和宿主消失；交易追加买不起、主动交换及道具重置。
测试日志和截图是证据，不把“没有报错”当作所有功能正确。

## 7. 交接模板

```text
目标：可观察行为或文档改进
查证：仓库文件、API 链接、日期与关键事实
修改：文件、配置、资源；公共接口与版本是否变化
不变量：保持不变的规则与兼容边界
验证：命令、退出结果、游戏构建、场景和观察
部署：未部署/本地测试/发布；源目标路径与哈希核对
风险：未查证事实、未游戏内验证的具体场景
后续：下一位开发者可以直接执行的检查或复现步骤
```

文档任务注明“运行时代码不变、未部署、未游戏内验证”即可；
不能为补齐表格编造实机结论。API 调用或行为改变后，先更新事实再更新结论。

## 8. GitHub 开发流程

仓库：[lanlandeli/penitent-relics](https://github.com/lanlandeli/penitent-relics)，默认分支 main。
Issues 记录 Bug 和功能规划；一次分支/PR 处理一个明确问题。模板位于 .github/。

工作区干净时，从 main 开始新任务；已有未提交修改先保留并明确归属，不直接切换或清理：

```powershell
git switch main
git pull --ff-only
git switch -c codex/your-change
```

按前文完成开发和验证，再检查差异、选择本次文件提交；路径需替换为实际文件：

```powershell
git diff --stat
git add -- path/to/changed-file
git diff --cached
git commit -m "Describe the change"
git push -u origin HEAD
```

在 GitHub 创建目标为 main 的 Pull Request，填写变更、验证与剩余风险；
等待 Validate 通过并检查 diff 后合并。任务开始和合并后同步 main，避免在过期分支持续开发。
不要强推 main；不要把其他参与者未完成的修改混入当前提交。

[Validate](../.github/workflows/validate.yml) 在 push、pull_request 和手动触发时运行：
Ubuntu 安装 Lua 5.3，检查 mod/tests 语法，自动执行全部 test_*.lua，解析 XML/ANM2 并检查提交空白。
它不需要本地 tools/lua/，不部署游戏、不发布 Steam Workshop，也不能代替实机验收。
失败时打开该次 Actions 日志，修复后推送同一分支重新检查。

正式发布前按第 6 节完成实测，再决定版本和 Release；开发提交无需逐次提升模组版本。
公开仓库的范围由 Git 跟踪文件决定，提交前检查 git status；忽略目录不会自动上传。
整个历史目录仅留本地；旧 Git 历史只在本机 archive/pre-github-20261009 分支保留。
仅推送当前任务分支，不使用 git push --all 或 --mirror，避免上传本地历史备份。

GitHub 机制参考：[Actions 文档](https://docs.github.com/en/actions/get-started/quickstart)。
