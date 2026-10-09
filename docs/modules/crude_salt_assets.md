# Crude Salt / 粗盐 — 规则与素材

当前模块版本：7.4.0。运行时素材为 PNG + ANM2。
攻击与组合登记见 [兼容清单](../development/attack_compatibility.md#3-模组攻击与效果登记)。

## 美术方向

粗盐以“干燥、粗粝、结晶、骤然碎裂”为核心，与 Trinity 的柔和圣光形成对比。

泪弹在生成时投一次概率；激光（科技、科技 X、硫磺火）与妈刀则在每次有效命中时投概率，
不设置持续武器触发间隔。重复成功只刷新同一份方向记录，不叠加减益层数。
动画应依靠逐帧轮廓变化表达材质，不使用烟雾、魔法光环或大幅代码缩放代替动作。

## 道具图标

- PNG：`mod/resources/gfx/items/collectibles/crude_salt.png`，32×32 RGBA。
- 主体为带松动软木塞的矮胖旧玻璃盐罐；正面分叉裂纹贯穿瓶身，少量粗盐从侧面漏出。
- 灰白玻璃、暖米色盐晶与深褐木塞形成三段明度，以深色粗轮廓保证底座和图鉴中的
  小尺寸辨识度。
- 正式 32×32 素材使用硬 Alpha 与有限色板，不使用平滑缩放产生的半透明轮廓或细碎渐变。
- 不使用容易被误读为石堆、白色三角形或普通材料包的轮廓。

## 原版泪弹

- 保留原版泪弹精灵及方向动画。
- 只施加暖灰白、米黄色的四级颗粒色阶。
- 泪弹表现使用染色，不生成拖尾实体。

## 方向盐晶标记

- PNG：`mod/resources/gfx/effects/crude_salt_mark.png`
- ANM2：`mod/resources/gfx/effects/crude_salt_mark.anm2`
- 图集：384×32，横排 12 帧，每帧 32×32。
- `Appear` 与 `Crack` 保留在素材中，但运行时不再播放。
- Lua 持有独立 `Sprite`，在 `onRender` 绘制标记。
- 精灵固定在 `Idle` 的清晰箭头帧并停止动画，不受效果实体自动清理影响。
- 代码按命中时保存的移动向量旋转盐晶，使标记直接表达机制方向。
- 标记在减益有效期间持续保持静态；重复命中只更新方向。
- 头顶位置综合 `PositionOffset`、`SpriteOffset`、`Size`、`SizeMulti` 与素材半高计算。

## 盐晶碎裂

- PNG：`mod/resources/gfx/effects/crude_salt_shatter.png`
- ANM2：`mod/resources/gfx/effects/crude_salt_shatter.anm2`
- 图集：960×96，横排 10 帧，每帧 96×96。
- `Shatter`：10 帧、16 tick、非循环；裂纹扩张后碎成粗盐块和少量颗粒。
- 普通敌人的原生冻结雕像到期时播放；Boss 触发反向判定时立即播放。
- 视觉实体由模块显式跟踪，并在 16 个逻辑帧后移除。
- 冻结前记录原怪的视觉尺寸与偏移；即使引擎替换为 `FrozenEnemy`，消失动画仍匹配原怪。
- 玩家碰到盐像时先播放粗盐碎裂并立即移除盐像，碰撞回调返回 `true` 跳过原版踢飞，
  因而不会滑行或转化为冰泪。

## 实体与生命周期

盐晶碎裂使用 `content/entities2.xml` 注册的 `Penitent Relics Crude Salt Visual` 中性变体；方向
标记是直接渲染的独立 `Sprite`。通用注册和清理方式见 [视觉规范](../development/custom_visuals.md)。

## 配置

以下为主要表现参数，完整默认值见 [模块 config](../../mod/modules/crude_salt/init.lua)。

```lua
tearPulseInterval = 3
shatterEffectFrames = 16
shatterSizeRatio = 2.2
shatterMinScale = 0.40
shatterMaxScale = 2.25
```
