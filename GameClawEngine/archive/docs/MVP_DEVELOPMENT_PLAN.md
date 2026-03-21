# AI 原生游戏引擎 MVP — 开发计划

> 最小可行产品的参考实现计划。代码库可能已演进到更晚阶段；当前状态见 [MVP_STATE.md](MVP_STATE.md)。

---

## 1. 项目背景与目标

你是一名熟练的 Godot 4.6 与 GDScript 开发者。

目标是构建一个**「AI 原生游戏引擎」**的最小 MVP，以 Godot 作为纯粹的「无头/渲染后端」使用。

**不会**在 Godot 编辑器里拖拽场景。所有内容必须通过 JSON（Game IR）动态生成。

**本 MVP 的最终交付物：** 一个能解析 JSON 字符串、生成 3D 盒子，并根据 JSON Patch 格式在不停游戏的情况下动态修改其颜色/位置的 Godot 运行时。

---

## 2. 技术栈

- **引擎：** Godot 4.6
- **语言：** GDScript
- **架构：** 数据驱动 / 纯代码实例化。实体不依赖 `.tscn` 继承。
- **通信：** 先做本地 JSON 字符串解析（HTTP/API 集成放在后续阶段）。

---

## 3. 实现阶段（不要一次性全做）

严格按步骤执行。执行某一阶段时，**只写该阶段的代码**，不要跳步。

### 阶段 1：IR 管理器与基础实例化

**目标：** 创建一个单例/管理器，读取写死的 JSON 字符串并生成一个 3D 对象。

**任务：**

1. 创建主场景 `main.tscn`，包含 Camera3D 和 DirectionalLight3D。
2. 创建 GDScript `IRManager.gd`（autoload 或挂到某个 Node 上）。
3. 定义表示初始 Game IR 的 JSON 字符串变量：
   ```json
   {"entities": [{"id": "box_1", "type": "cube", "color": "#FF0000", "position": [0,0,0]}]}
   ```
4. 实现函数 `parse_and_spawn()`：解析该 JSON，实例化带 BoxMesh 的 `MeshInstance3D`，应用带十六进制颜色的 `StandardMaterial3D`，设置位置，并加入场景树。
5. 用字典把 `id`（如 "box_1"）映射到实际的 Godot 节点引用，供后续使用。

### 阶段 2：JSON Patch 应用

**目标：** 能用 JSON Patch 数组修改已生成的对象。

**任务：**

1. 定义表示一次修改的 patch 字符串变量：
   ```json
   [
     {"op": "replace", "path": "/entities/box_1/color", "value": "#0000FF"},
     {"op": "replace", "path": "/entities/box_1/position", "value": [2, 0, 0]}
   ]
   ```
2. 在 `IRManager.gd` 中实现函数 `apply_patch(patch_json_string)`。
3. 该函数需解析 patch 数组，从 path 中取出 `id`，在字典中找到对应节点，并动态更新其材质颜色和位置。

### 阶段 3：UI 控制器（模拟 AI 输入）

**目标：** 在 Godot 里加一个简单 UI，用于触发 patch，证明热更新有效。

**任务：**

1. 在 `main.tscn` 的 UI 里添加一个 `Button`。
2. 连接按钮的 `pressed` 信号。
3. 按下时调用 `apply_patch()`，传入阶段 2 的测试 patch。盒子应立刻变蓝并移动。

---

## 4. 编码规范与最佳实践

- GDScript 保持简洁，**完整类型标注**（如 `var id: String`），并用注释说明逻辑。
- 本 MVP **不要**使用复杂物理或信号，只做纯视觉。
- 用 `JSON.parse_string()` 妥善处理 JSON 解析错误。
