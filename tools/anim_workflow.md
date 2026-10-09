# 游戏资源与动画工具工作流

规范见 [custom_visuals.md](../docs/custom_visuals.md)；本页只说明工具与文件流转。

## 1. 定位工具

在实际游戏安装目录的 tools 下查找 ResourceExtractor 和 IsaacAnimationEditor。
当前部署脚本配置的游戏根目录为
`E:\SteamLibrary\steamapps\common\The Binding of Isaac Rebirth`；
该盘符是本机配置，不是所有机器的固定位置。

使用游戏随附工具的说明确认命令行参数，不将旧文档中的调用格式当作所有版本通用。
解包输出放被 Git 忽略的 ExtractedResources/ 或仓库外，仅用于研究结构；
不要放入 mod/。分发素材前遵守游戏随附资源说明和素材授权。

## 2. 编辑与保存

1. 先在 docs/<module>_assets.md 记录用途、尺寸、图集、动画名、时间线、Pivot 和清理条件。
2. 用 Animation Editor 打开自己的 ANM2，参考现有素材结构，不直接复制原版图像发布。
3. 保存到 mod/resources/gfx/effects/，图集与 ANM2 同目录且带模块 ID 前缀。
4. Sprite.Load 写 gfx/effects/...anm2；XML 的 anm2path 相对 anm2root。
5. 在编辑器检查裁切、层、循环、完整播放和关键帧 Delay；
   再完成 XML 解析、PNG 格式与游戏内验证。

自定义效果实体使用 content/entities2.xml 注册中性变体；
不使用旧教程的固定 variant=600 示例，不把动画放入 mod/gfx。
原生武器改色优先保留原 sprite；真正改泪弹变体需单独验证方向动画和协同。

## 3. 源稿、过程稿与生成工具

- tools/assets/ 保存仍有维护价值的源稿；mod/resources/ 只放运行时产物。
- 历史目录里的占位脚本仅供参考，带有旧硬编码输出路径，不能用于覆盖当前正式图标。
- process_forbidden_fruit_assets.py 仍保留用于参考制作过程，但会输出旧藤蔓等素材；
  不应把它当作“重建当前全部美术”的可靠入口。修改/运行前检查输出并隔离比较。
- 预览需要同时展示原尺寸与最近邻放大；大图好看不能替代原尺寸辨识度。

## 4. 验证后部署

按 [agent_workflow.md](../docs/agent_workflow.md) 运行全量测试和资源检查。
通过后部署 mod/ 到本地游戏、核对哈希并完全重启，再记录视觉场景。
动画预览、XML 解析和离线 mock 均不能代替游戏实际播放。