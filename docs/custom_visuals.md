# 自定义视觉、动画与音效

这是项目的资源制作与运行时约定，不是所有以撒模组必须采用的唯一方案。
代码入口见 [framework_api.md](framework_api.md)，工具操作见
[anim_workflow.md](../tools/anim_workflow.md)，资料依据见 [api_research.md](api_research.md)。

## 1. 先选择表现方式

| 需求 | 优先方案 | 模块责任 |
|---|---|---|
| 原武器主题色 | 短时 SetColor | 控制持续时间与优先级，检查与原版染色的组合 |
| 静态头顶印记 | 独立 Sprite | 锚点、可见条件、数据清理 |
| 需要跟随特定武器的覆盖动画 | 对应实体 Render 回调 + 独立 Sprite | 每逻辑帧推进一次，Render 只绘制 |
| 场景中的独立特效 | 注册中性 ENTITY_EFFECT 变体 | 创建、碰撞禁用、跟随、清理 |
| 真正改变泪弹外观/变体 | 单独设计并验证的自定义泪弹 | 方向动画、原版变体和协同兼容 |

单纯染色不替换原武器 sprite。确需新变体时，不套用“variant 从 600 起一定安全”的旧教程。
注册唯一名称并运行时解析，检查是否与已有内容冲突。

自定义效果不能用 POOF01 等原生行为变体当容器：替换 ANM2 不会移除变体本身的引擎逻辑。
这是仓库已有视觉问题形成的约束；不能因此推断所有原生效果都具有相同生命周期。

## 2. 资源路径

| 用途 | 仓库位置 | 代码/XML 中写法 |
|---|---|---|
| 道具图标 | mod/resources/gfx/items/collectibles/<id>.png | items.xml 的 gfx 写文件名，沿用现有 gfxroot |
| 效果动画 | mod/resources/gfx/effects/<id>_<effect>.anm2 | Sprite:Load 使用 gfx/effects/...anm2 |
| 效果图集 | 与 ANM2 同目录 | Spritesheet Path 写同目录 PNG 文件名 |
| 实体声明 | mod/content/entities2.xml | anm2path 相对 anm2root |
| 可维护的源稿 | tools/assets/ | 不参与部署 |
| 被替代的过程稿 | 历史/ | 不参与部署 |

路径大小写必须与磁盘一致；资源归属用模块 ID 前缀表达。
PNG 为 RGBA；像素图标按最终 32×32 验收，再用最近邻放大查边缘。
透明图可以原生带 Alpha，也可以色键去背；最终检查透明边缘、残色和裁切。
硬轮廓像素图避免平滑缩小；柔光特效可以有半透明渐变，不能一概要求硬 Alpha。

## 3. 注册中性效果实体

在现有 entities 根节点追加，不复制一个新的根节点：

```xml
<entity id="1000" name="Penitent Relics Example Visual"
    anm2path="example_visual.anm2" collisionDamage="0" collisionMass="0"
    collisionRadius="0" friction="1" gridCollision="none"
    numGridCollisionPoints="0" shadowSize="0"/>
```

本仓库根节点为 `<entities anm2root="gfx/effects/" version="5">`。
这里 id=1000 是 ENTITY_EFFECT 的类型，不是道具本地 ID。
省略 variant 让引擎分配，随后用 Isaac.GetEntityVariantByName 解析；
并非“name 本身决定一个固定数字”。
[entities2.xml 文档](https://cuerzor.github.io/IsaacDocs/rep/xml/entities2.html)
对部分目录行为标有未测试，当前仓库的布局仍需目标游戏验证。

在 onRegister 解析名称；结果无效时只警告一次并跳过该视觉，规则继续运行。
现有 Crude Salt/Trinity 有 EFFECT_NULL 降级路径，这是现有实现，
不应将其宣传成所有新模块都必需的“双兜底”。
模块须明确选择降级方案并验证，禁止改用 POOF01。

生成函数应检查 ToEffect 转换，使用 ENTCOLL_NONE 与 COLLISION_NONE，接受实际动画名参数。
持续效果可用 SetTimeout(-1) 并由模块显式清理；不要把该值当成自动清理机制。
参考 [Trinity spawnVisual](../mod/modules/trinity/init.lua)，
调用方收到 nil 时必须跳过表现，不能中断已完成的规则结算。
不要求所有动画都叫 Idle：现有 Pulse、Shatter、Q0–Q4 都有独立用途。

## 4. 时间线与推进

当前素材中，Animation.FrameNum 已表示动画时间线长度；LayerAnimation 下各关键帧的
Delay 之和描述该层时间跨度。**不能将 FrameNum 再乘以 Delay。**
例如 trinity_laser_muzzle 的 Pulse 是 38 tick，关键帧 Delay 为
3+4+5+5+7+7+4+3=38；图集中只有 8 张图，不代表只有 8 tick。

每份动画核对：

- 动画名、Loop、FrameNum、各层 Delay 总和，RootAnimation 与层时间线是否匹配；
- 图集宽高、XCrop/YCrop、Width/Height、Pivot，不超出 PNG；
- PlaybackSpeed、推进频率、到期时刻；变速后不能机械用静态长度当逻辑寿命；
- 循环特效随宿主存在而播放；一次性特效有明确的结束和兜底清理。

独立 Sprite 在逻辑更新中调用 Update，每个逻辑帧最多一次；实体自身的 sprite 由引擎推进，
不额外重复推进。静态标记使用 SetFrame/Stop。
不要每帧 Play(..., true) 将动画重置到开头。
[Sprite API](https://cuerzor.github.io/IsaacDocs/rep/Sprite.html#update)

动画的主要动作在素材中表达；位置跟随、轨道、适配尺寸与细微呼吸可以由代码控制。
38 tick 是本项目激光脉冲素材规格，不是所有硫磺火寿命的通用保证。

## 5. 染色与坐标

`Entity:SetColor(color, duration, priority, fadeout, share)` 的第二参是持续时间，
不是淡入时间；false 的 fadeout 也不能证明存在颜色插值。
反复更换色阶是否平滑需实机观察，不承诺自动混合或完全兼容其他染色。
[Entity.SetColor](https://cuerzor.github.io/IsaacDocs/rep/Entity.html#setcolor)

世界位置、视觉偏移和屏幕位置分别处理；同一偏移只加一次。
优先使用对应实体的 Render 回调 offset，避免在全局 Render 中猜测该实体本次插值位置。
Trinity 当前对圆形激光采用 WorldToScreen(laser.Position) + offset，
直线激光采用自身路径/起射位置逻辑；这是该模块的实现策略，不是所有特效的统一公式。
大小适配根据需要使用 Size、SizeMulti、SpriteScale 和素材 Pivot，避免重复应用缩放。

测试提供明显非零的 offset、变化的角色尺寸和移动的激光圆环；
零偏移截图无法证明对齐正确。

## 6. 生命周期清理

| 结束条件 | 清理责任 |
|---|---|
| 到期或规则状态消失 | 移除自己创建的视觉并删除记录 |
| 宿主死亡、Ref 为 nil、Exists 为 false | 不再访问宿主；清理视觉及记录 |
| 换房间、新游戏 | 清空房间引用；按设计重建本局仍有效的表现 |
| 保存继续 | 从规则数据重建，不保存 Sprite 或实体指针 |
| 失去道具 | 按设计终止或保留已结算状态；例如禁果本层惩罚不因失去本体而消失 |

跨帧实体引用用 EntityPtr。清理函数应可重复调用；
当宿主失效但视觉仍存在时，先移除视觉，不能只删列表造成残留。
仅清理模块自己的视觉实体，不移除战斗实体代替正常伤害。

在最窄的 Update 生命周期遍历已跟踪列表，不为清理每帧扫描全房间。
独立 Sprite 清理时释放模块引用，无需 Entity:Remove。

## 7. 音效

SFXManager 在注册时创建，调用 Play(id, volume, frameDelay, loop, pitch, pan)。
FrameDelay 是允许同音效再次播放前的帧数，不是延迟开始播放。
高频命中或同帧多个效果仍需节流；循环音效必须有停止条件。
[SFXManager.Play](https://cuerzor.github.io/IsaacDocs/rep/SFXManager.html#play)

优先使用合适的原生 SoundEffect，音量、音高和开关进入配置。
自定义音效不是框架禁止项；确有需求时核对 sounds.xml、格式和来源授权后另行接入。
没有这一需求时，不为预留能力添加音频资源或新框架。

## 8. 验收

离线验证路径、动画名、变体选择、到期前一帧/到期帧、循环重播、重复创建和清理。
Mock 只实现实际调用的方法，并模拟失效、类型转换失败及配置关闭。
XML 可解析不证明引擎会播放；必须记录原尺寸图标、完整动画、移动锚点、
宿主消失与换房残留的实机场景。未验证时明确写“未游戏内验证”。