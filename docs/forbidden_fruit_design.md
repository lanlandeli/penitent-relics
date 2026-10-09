# Forbidden Fruit / 禁果 — 规则与实现

当前模块版本：3.1.0；模块 ID：`forbidden_fruit`；内容本地 ID：`1002`。

本页记录交易、楼层伤害和表现规则。与其他攻击的数值关系见
[兼容清单](attack_compatibility.md#4-组合检查)。

## 1. 核心规则

每层初始房间生成两件 Treasure Pool 临时道具，玩家离房前可以付费选择其中一件：

- 两件使用同一个非零 `OptionsPickupIndex`，只能选择一件；
- 每件固定为一颗心的原生恶魔交易；Keeper / Tainted Keeper 支付原生金币价格；
- 成功购买后，选择者本层根据最终道具品质降低 0/10/20/30/40% 伤害；
- 未购买便离开初始房时，两件立即失效，不播放拒绝反馈；
- 拒绝没有任何惩罚，未支付任何资源；
- 交易支付永久生效，品质伤害降低只持续当前层；

## 2. 生成和拒绝

至少一名存活玩家在进入新层时持有 Forbidden Fruit，才在初始化完成后的下一逻辑帧生成一组
选择。两件道具使用楼层种子从 Treasure Pool 确定性抽取，让原生道具池处理 Chaos、NO!、
Sacred Orb、Tainted Lost 和挑战限制。持有多份 Forbidden Fruit 仍只生成一组。

第一层启动时 `onGameStart` 与 `MC_POST_NEW_LEVEL` 可能报告同一楼层。
用 `floorKey` 去重，生成前清理同一 `OptionsPickupIndex` 的旧成员，保持一组两个选项。

中途获得不补发，下一层开始生效；生成后失去本体不删除当层选择。Greed/Greedier、Ascent、
Home、Death Certificate、Genesis 和调试剧情房间不生成。XL 整张地图只生成一次。

离开初始房时若尚未成功购买，模块立即移除所有选项和品质视觉并将本层标记为拒绝；重新进入
不会再生成。Moving Box 在选择未结算时使用会直接使机会失效，避免临时道具被带走。

## 3. 原生交易价格

每个选项配置：

```lua
pickup.ShopItemId = -2
pickup.Price = isKeeper and 15 or PickupPrice.PRICE_ONE_HEART
pickup.AutoUpdatePrice = false
```

固定负价格表示一心交易；`ShopItemId = -2` 启用引擎的恶魔交易底座语义并避免特殊房间的异常
商店槽位定价。初始房必须关闭自动更新，否则普通角色的 Lua 生成底座会被错误改成 15¢ 商店
价格。Keeper/Tainted Keeper 由模块固定为 15¢；引擎仍负责购买资格、心容器/金币支付、购买动画和交易统计。

支付由原生交易执行。玩家与带 Forbidden Fruit
私有标记、业务组和实体种子的底座碰撞时，只记录选择者与碰撞时的动态 `SubType`；该同一实体被
原生 `MC_POST_ENTITY_REMOVE` 移除时才结算。主动交换不移除底座，而是由
`MC_POST_PICKUP_UPDATE` 观察同一实体变成换下来的主动后结算，并把它恢复为免费普通底座。
买不起时具体底座既不移除也不变形，因此不激活倍率。

选项身份以 Forbidden Fruit 的底座实体、种子和 `OptionsPickupIndex` 为准，不以生成瞬间的道具
ID 为准。碰撞时读取底座当前 `SubType`，因此 D6、堕化以撒和 Glitched Crown 等改变展示道具的
机制以最终取得的道具品质结算。单纯重置道具或替换实体不触发成交。

`Game():GetDevilRoomDeals()` 不作为成交信号：实机证据表明，初始房中设置 `ShopItemId = -2` 的
Lua 生成底座虽然执行原生付款，却不会增加该计数。普通角色、Keeper 和 Lost 统一依赖“本模块
底座碰撞候选 + 实际取得道具”确认，不观察生命、金币或房间内其他底座。

Void、Abyss 与 Moving Box 不能绕过付费逻辑：在未结算选项仍存在时使用，会立即使本层机会
失效并移除底座，不提供免费吞噬或装箱收益。复制品仍属于同一个业务组，最终最多成功结算一次；
Diplopia、Crooked Penny、Glitched Crown、Flip、D6/D100 需实机复验。

## 4. 品质伤害降低

| 最终品质 | 本层伤害倍率 |
|---:|---:|
| Q0 | ×1.00 |
| Q1 | ×0.90 |
| Q2 | ×0.80 |
| Q3 | ×0.70 |
| Q4 | ×0.60 |

品质读取玩家实际获得的最终道具 `ItemConfigItem.Quality`。通过 `MC_EVALUATE_CACHE` 的
`CACHE_DAMAGE` 应用乘法，在成功购买、恢复存档和进入下一层时重算缓存。

进入下一层只清除本层品质、倍率和头顶印记；已支付的心容器或金币永不返还。失去 Forbidden
Fruit 本体也不提前清除已结算的当层减伤。

## 5. 状态与持久化

玩家 `GetData()` 键：

- `pr_forbidden_fruit_active`
- `pr_forbidden_fruit_quality`
- `pr_forbidden_fruit_damage_mult`

底座键：

- `pr_forbidden_fruit_option`
- `pr_forbidden_fruit_group`
- `pr_forbidden_fruit_original_seed`

跨帧引用使用 `EntityPtr`，表索引使用 `GetPtrHash`。
存档写入模组共用的 SaveData，格式为 FF3，兼容 FF2；扩展协议见 [架构](architecture.md#4-状态按生命周期归属)。
继续游戏时恢复 spawned/resolved/declined、选项 ID、选择者品质与伤害倍率，保持交易只结算一次。

## 6. 表现

道具图标为暗红禁果、白色咬痕、黑蛇和黄色蛇眼。
选择场景使用原生底座与购买反馈。

选择者头顶的品质 debuff 印记：Q0–Q4 分别播放
`forbidden_fruit_debuff.anm2` 的同名循环动画，并跟随实际选择者持续到换层清除倍率。该视觉只读取
玩家的倍率状态，通过独立 `safeCall` 更新，与交易和属性结算分开。
品质叶片与选择动画的素材留存，当前运行时不加载。

## 7. 内容文案

EID 与内置图鉴使用以下规则说明：

```text
At each floor start, choose one of two Treasure Room items before leaving
Each choice is a one-heart devil deal; Keepers pay coins
Chosen quality reduces damage by 0/10/20/30/40% for the floor
Refusing has no penalty
```

Forbidden Fruit 只进入 Secret Room 池，默认权重保持现有配置。

## 8. 自动测试

至少覆盖：

- 无持有者不生成，出生持有生成两件，同组选项且每层只一组；
- 第一层重复生命周期通知不生成第二组，生成前会清除同组陈旧底座；
- 普通角色固定一心价格，Keeper 固定 15¢，两者关闭非商店自动换价；
- 买不起时底座存在且不结算，成功获得后只结算一次；
- Q0–Q4 倍率正确，下一层清除倍率但不执行任何退款；
- 未选择离房立即失效且拒绝零惩罚；
- D6 后按最终道具、保存继续、Moving Box 与复制品状态幂等；
- debuff 印记按 Q0–Q4 生成，并在换层、死亡、新游戏和倍率失效时清理。

## 9. 游戏内验证

自动检查通过后先做本地测试部署，再实测下列场景并记录结果：

1. 普通红心角色显示一心价格，成功购买永久少一容器；
2. 只剩一容器、买不起及纯魂心角色的原生购买资格；
3. Keeper 与 Tainted Keeper 显示原生金币价格，金币不足不能购买，成功后正确扣币；
4. Lost、骨心、Your Soul、A Pound of Flesh；
5. Q0–Q4 面板倍率与下一层恢复；
6. D6、D100、Glitched Crown、Flip、Diplopia、Crooked Penny、Moving Box；
7. 未选择离房、传送离房以及未选择/已选择/已拒绝三种保存继续状态；
8. 头顶品质印记、原生拾取音效；品质叶片和附加吞噬表现保持禁用。
