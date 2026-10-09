# Lua 与文档风格

本页约定命名、格式和常用写法。接口见 [框架参考](framework_api.md)。

## 1. 命名、语言与格式

| 范围 | 规则 | 示例 |
|---|---|---|
| 模块 ID / 目录 | 小写英文和下划线 | crude_salt |
| 函数、局部变量、字段 | lowerCamelCase | updateSaltMarks |
| 模块私有常量 | UPPER_SNAKE_CASE | KEY_DEBUFF |
| 模块 GetData 键 | pr_<module_id>_<name> | pr_crude_salt_debuff |
| 框架归属标记 | 只通过 setMark/hasMark 访问 | 不直接修改 penitentrelics_ 键 |
| 游戏文本、Lua/XML/工具注释、日志 | 英文 | [PenitentRelics] |
| 开发文档 | 中文，可保留英文 API 名 | 不翻译标识符 |

Lua 使用 4 空格、尽量不超过 100 字符。XML/ANM2 局部编辑沿用文件缩进，不整体格式化。
注释解释引擎约束与设计原因，不复述语句；删除失效说明，不堆积注释掉的旧代码。
Markdown 用相对链接连接仓库文件；示例标明可直接运行还是需要替换名称的片段。

## 2. 函数与模块

优先早返回，一个函数负责一个明确动作；避免同时投概率、改状态、结算伤害并创建表现。
模块顶层只定义常量与函数，运行时 ID 和可重置状态在生命周期内初始化。
只 include 自己的私有 helper；不重新加载 framework 取得另一套 Manager。

目标检查按引用存在 → Exists → 类型符合 → 未死亡的顺序进行。
不要先对可能失效的引用调用 IsDead。纯配置/数学 helper 尽量不依赖 Isaac 全局，便于测试。
性能优化先检查逐帧重复扫描和分配，函数划分保持清晰。
[IsaacDocs 代码实践](https://wofsauge.github.io/IsaacDocs/rep/tutorials/GoodPractices.html)

## 3. Lua 5.3 兼容子集

使用 Lua 5.3 的位运算和 table.unpack；新增库调用先确认游戏运行时提供该接口。
含 nil 的可变参数转发用 select("#", ...) 记录数量，再 table.unpack(args, 1, count)；
嵌套闭包不可直接引用外层 ...。

允许 false 的配置用 nil 判断缺省值，保留 false 与 nil 的区别。
Entity userdata 不作跨回调表键；GetPtrHash 用于运行期索引，EntityPtr 用于跨帧引用。
不把哈希、指针或 Sprite 序列化到存档。

## 4. 状态与概率

状态只写模块命名空间；每份状态定义初始化、刷新、终止和重建路径。
清理应可重复执行。移除标记时不整体替换实体 GetData，不清掉其他模块数据。
规则 RNG 与视觉表现分离；不在 Render 投玩法概率，不以随机新通道绕开伤害去重。
参考教程中的 RNG 与缓存说明，不在模块间复制来源解析和伤害锁。

## 5. 配置、错误与日志

可调数值放 module.config；全局覆盖放 mod/config.lua，读取用 cfg/getConfig。
新键记录单位、有效范围、重复持有与极值行为；不要在多个函数复制默认值。
配置表按只读处理；静态浅合并不是动态配置机制。

使用 Util.log/warn，避免逐帧重复警告。
safeCall 是 Lua 异常边界，不是事务：报错前产生的实体和状态需自行处理。
额外回调的 enabled 检查、safeCall 与返回传播由模块实现，不能返回 safeCall 的成功标志
冒充原生回调结果。

## 6. 测试与维护

测试使用最小但真实的语义桩，断言结果、重复触发和失败路径；
不要把实现逐行翻译成测试，或让关键 API 永远成功。
独立运行每个 test_*.lua，避免全局 mock 在测试间串用。
文档示例通过语法检查；引擎行为另在游戏中验证。

修改格式时保留现有开发改动。文档分工与入口见 [目录](README.md)。
