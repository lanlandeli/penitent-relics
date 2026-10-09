# 自定义视觉、动画与音效

资源制作见 [工具流程](../../tools/anim_workflow.md)；涉及伤害或命中效果时，另查
[攻击兼容](attack_compatibility.md)。

## 1. 先选择表现方式

| 需求 | 优先方案 | 模块责任 |
|---|---|---|
| 原武器主题色 | 短时 SetColor | 控制持续时间与优先级，检查与原版染色的组合 |
| 静态头顶印记 | 独立 Sprite | 锚点、可见条件、数据清理 |
| 需要跟随特定武器的覆盖动画 | 对应实体 Render 回调 + 独立 Sprite | 每逻辑帧推进一次，Render 只绘制 |
| 场景中的独立特效 | 注册中性 ENTITY_EFFECT 变体 | 创建、碰撞禁用、跟随、清理 |
| 真正改变泪弹外观/变体 | 单独设计并验证的自定义泪弹 | 方向动画、原版变体和协同兼容 |

单纯染色保留原武器 sprite；新变体注册唯一名称并在运行时解析。
自定义场景动画使用中性效果变体；POOF01 等原生变体在替换 ANM2 后仍带有原生行为。

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
硬轮廓像素图使用最近邻缩放；柔光特效可保留半透明渐变。

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
省略 variant 让引擎分配，随后用 Isaac.GetEntityVariantByName 解析。
字段说明见 [entities2.xml](https://cuerzor.github.io/IsaacDocs/rep/xml/entities2.html)。

在 onRegister 解析名称；结果无效时记录一次警告并跳过表现，保留已完成的规则结算。

生成函数应检查 ToEffect 转换，使用 ENTCOLL_NONE 与 COLLISION_NONE，接受实际动画名参数。
持续效果可用 SetTimeout(-1)，结束时由模块显式清理。
参考 [Trinity spawnVisual](../../mod/modules/trinity/init.lua)，
调用方处理 nil 结果；动画名与素材保持一致，例如 Idle、Pulse、Shatter、Q0–Q4。

## 4. 时间线与推进

当前素材中，Animation.FrameNum 已表示动画时间线长度；LayerAnimation 下各关键帧的
Delay 之和描述该层时间跨度。**不能将 FrameNum 再乘以 Delay。**
例如 trinity_laser_muzzle 的 Pulse 是 38 tick，关键帧 Delay 为
3+4+5+5+7+7+4+3=38；图集中只有 8 张图，不代表只有 8 tick。

动画检查项：

- 动画名、Loop、FrameNum、各层 Delay 总和，RootAnimation 与层时间线是否匹配；
- 图集宽高、XCrop/YCrop、Width/Height、Pivot，不超出 PNG；
- PlaybackSpeed、推进频率、到期时刻；变速后不能机械用静态长度当逻辑寿命；
- 循环特效随宿主存在而播放；一次性特效有明确的结束和兜底清理。

独立 Sprite 在逻辑更新中调用 Update，每个逻辑帧最多一次；实体自身的 sprite 由引擎推进，
不额外重复推进。静态标记使用 SetFrame/Stop。
不要每帧 Play(..., true) 将动画重置到开头。
[Sprite API](https://cuerzor.github.io/IsaacDocs/rep/Sprite.html#update)

动画的主要动作在素材中表达；位置跟随、轨道、适配尺寸与细微呼吸可以由代码控制。

## 5. 染色与坐标

`Entity:SetColor(color, duration, priority, fadeout, share)` 的第二参是持续时间，
色阶切换的平滑程度和覆盖优先级在游戏中检查。
[Entity.SetColor](https://cuerzor.github.io/IsaacDocs/rep/Entity.html#setcolor)

世界位置、视觉偏移和屏幕位置分别处理；同一偏移只加一次。
优先使用对应实体的 Render 回调 offset，避免在全局 Render 中猜测该实体本次插值位置。
Trinity 当前对圆形激光采用 WorldToScreen(laser.Position) + offset，
直线激光采用自身路径/起射位置逻辑。按具体实体的坐标约定选择计算方式。
大小适配根据需要使用 Size、SizeMulti、SpriteScale 和素材 Pivot，避免重复应用缩放。

对齐测试覆盖非零 offset、角色尺寸变化和移动的激光圆环。

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
自定义音效通过 sounds.xml 接入，核对格式、资源路径和素材来源。

## 8. 验证

资源改动检查路径、动画名、尺寸与时间线；生命周期改动检查创建、到期与清理。
游戏内按改动观察原尺寸图标、动画播放或锚点跟随。
修改表现参数复用现有测试，新增逻辑再补对应断言；范围选择见 [工作流](agent_workflow.md)。
