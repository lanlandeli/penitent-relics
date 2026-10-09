# Trinity / 三位一体 — 素材与表现

对应模块 2.7.3。玩法规则见 [设计契约](trinity_design.md)；
通用格式、注册、坐标和验收要求见 [视觉规范](custom_visuals.md)，
制作步骤见 [美术工具流程](../tools/anim_workflow.md)。
以下规格描述当前资源，不作为当前构建已完成实机验收的证明。

## 1. 资源清单

除图标外，文件均位于 mod/resources/gfx/effects/，每项包含同名 PNG 和 ANM2。
表中帧数指图集关键帧；时长指 ANM2 逻辑 tick，不能用 FrameNum 再乘 Delay。

| 素材 | PNG 尺寸 / 单帧 | 动画 | 形状与锚点 |
|---|---|---|---|
| trinity.png | 32×32 | 无 | 白、金、冰蓝三环与十字；位于 gfx/items/collectibles/ |
| trinity_orb | 256×32 / 32×32，8 帧 | Idle，16 tick，循环 | 中性乳白光种，代码按位格染色 |
| trinity_mark_father | 32×32，1 帧 | Idle，循环 | 白色十字，与 Son 图标可区分 |
| trinity_mark_son | 32×32，1 帧 | Idle，循环 | 金色闭合圆环 |
| trinity_judgment | 960×160 / 96×160，10 帧 | Idle，24 tick，不循环 | 三束窄圣光；底部中心 Pivot=(48,160) |
| trinity_judgment_ring | 2304×192 / 192×192，12 帧 | Idle，24 tick，不循环 | 三道不完整光弧；中心 Pivot=(96,96)，ANM2 提供地面透视 |
| trinity_laser_muzzle | 384×48 / 48×48，8 帧 | Pulse，38 tick，不循环 | 中性光种展开为三片细弧，无实心块、符文、烟雾或拖尾 |

PNG 保持 RGBA；ANM2 图集引用为同目录文件名，Lua 加载路径以 gfx/ 起始。
效果实体使用 [entities2.xml](../mod/content/entities2.xml) 注册的中性变体
Penitent Relics Trinity Visual；按名称解析，再加载所需动画。
激光起射使用独立 Sprite，不创建效果实体；不得用 POOF01 承载自定义动画。

## 2. 跟随、染色与渲染

- 光球：三颗共用动画，按暖白、金、冰蓝染色；相隔 120°，默认半径 28、
  逆时针角速度 0.04 rad/逻辑帧，代码维护椭圆环绕与前后景透视。无实体或地形碰撞。
- 印记：Father 左、Son 右，按目标体型定位；默认头顶留白 6、横向偏移 8，
  缩放使用 markSizeRatio/min/max 配置。只有两种持续印记，Spirit 不增加第三个长期图标。
- 泪弹：保留原版精灵和方向动画，每 3 帧切换预制明暗色阶，SetColor 持续 4 帧；
  Duration 不代表淡入时长。没有额外 PNG、覆盖实体或拖尾。
- 激光和妈刀：短时位格染色，保留原生 Variant、光路与碰撞；不承诺与其他模组的染色互不覆盖。
- 翅膀：使用原版 Revelation costume 的运行期引用，失去道具或死亡时移除本模块维护的外观。

审判光柱和地面光弧使用素材的 24 tick 时间线，代码负责定位、层级和结束清理，
不逐帧覆写素材的缩放、旋转和透明度；不加屏幕震动。
光晕视觉范围和 judgmentAoeRadius 分别验收，不能从素材边缘推导伤害范围。
审判播放一次 SOUND_ANGEL_BEAM，默认音量 0.90、音高 1.00，重播间隔 6 帧；
开关与数值来自模块配置。

## 3. 激光起射定位

Pulse 由逻辑 Update 推进；首次有效激光更新后播放，根仍存活则按 38 tick 周期重播。
独立 Sprite 分两层绘制：半透明外层柔光与清晰内层三弧，核心默认缩放 1.10，
伴随呼吸缩放、轻微旋转和位格染色。

- 直线激光优先使用 GetSamples() 的首个路径点，再叠加 PositionOffset；
  缺少有效采样时按源码回退，不硬编码嘴部像素补偿。
- 科技 X 等圆形激光在对应 onLaserRender 中使用
  WorldToScreen(Position) + RenderOffset，跟随本次实际绘制位置。

需检查移动、角色缩放、变身、不同射向、圆形光束和永续光束。
渲染不得推进位格或伤害计时。

## 4. 清理与维护检查

印记随到期、目标死亡或规则清除移除；光球与翅膀随持有/生存状态维护。
审判按时长结束；起射随根失效结束；换房和新局清理对应临时记录。
准确状态归属与重置行为见 [设计契约](trinity_design.md#5-状态与生命周期)。

修改素材后，核对 PNG 尺寸与 RGBA、ANM2 引用/动画名/时长、Lua 路径和原尺寸可读性；
实机检查完整周期、层级、双印记不重叠、激光对齐及宿主消失后的清理。
检查和测试部署顺序统一见 [工作流](agent_workflow.md)，不在素材清单重复部署命令。