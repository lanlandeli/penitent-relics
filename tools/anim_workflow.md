# 游戏资源与动画工具工作流

本页说明工具与文件流转，资源规格见 [视觉规范](../docs/development/custom_visuals.md)。

## 1. 定位工具

在实际游戏安装目录的 tools 下查找 ResourceExtractor 和 IsaacAnimationEditor。
游戏路径以本机安装位置为准，部署前核对 tools/deploy.bat 的配置。

工具参数以当前安装附带的说明为准。
解包输出放被 Git 忽略的 ExtractedResources/ 或仓库外，仅用于研究结构；
不要放入 mod/。分发素材前遵守游戏随附资源说明和素材授权。

## 2. 编辑与保存

1. 在 `docs/modules/<module>_assets.md` 记录用途、尺寸、图集、动画名、时间线、Pivot 和清理条件。
2. 用 Animation Editor 打开自己的 ANM2，参考现有素材结构，不直接复制原版图像发布。
3. 保存到 mod/resources/gfx/effects/，图集与 ANM2 同目录且带模块 ID 前缀。
4. Sprite.Load 写 gfx/effects/...anm2；XML 的 anm2path 相对 anm2root。
5. 在编辑器检查裁切、层、循环、完整播放和关键帧 Delay；
   再完成 XML 解析、PNG 格式与游戏内验证。

自定义效果实体使用 content/entities2.xml 注册中性变体，在运行时按名称解析。
原生武器改色优先保留原 sprite；真正改泪弹变体需单独验证方向动画和协同。

## 3. 源稿、过程稿与生成工具

- tools/assets/ 保存仍有维护价值的源稿；mod/resources/ 只放运行时产物。
- process_forbidden_fruit_assets.py 的输出包含旧藤蔓素材；运行前确认输出路径和需要保留的产物。
- 预览同时展示原尺寸与最近邻放大，检查辨识度和像素边缘。

## 4. 验证后部署

按 [工作流](../docs/development/agent_workflow.md) 检查修改过的资源；涉及 Lua 时追加代码检查。
通过后部署 mod/ 到本地游戏、核对哈希并完全重启，再记录视觉场景。
实机观察本次修改的播放、锚点或清理行为。
