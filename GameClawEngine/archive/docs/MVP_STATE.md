# GameClawEngine MVP — 当前状态（供 AI 评估下一步计划）

## 一、定位与目标

- **定位**：AI 原生游戏引擎 MVP。AI 是第一开发者，通过结构化数据（Game IR）驱动游戏状态；Godot 仅作「运行时投影」与渲染/物理，不承载玩法逻辑。
- **首期目标**：在单机本地跑通「自然语言/IR → Patch → 引擎画面更新」的技术流，并支持 AI 通过 MCP 自主观察、修改、验证状态。

---

## 二、已实现能力

### 2.1 核心架构（Godot 4.6 + GDScript）

| 组件 | 说明 |
|------|------|
| **IRManager**（autoload） | Game IR 唯一事实源；加载初始 TOON 状态、应用 Patch、维护实体→节点映射、发出 patch_applied/patch_failed 等信号。 |
| **Codec 接口** | 抽象编解码：`encode(data)->String`, `decode(text)->Dictionary`。当前实现：TOONCodec（主）、JSONCodec（兜底）。 |
| **PatchEngine** | RFC 6902 风格 Patch 执行（add/replace/remove/test）；ACID：失败则自动回滚，并维护 patch 历史。 |
| **IRValidator** | IR 数据结构校验（实体类型、必填字段等），在加载与 apply 前执行。 |
| **EntityFactory** | 根据 IR 实体类型创建 Godot 节点（如 cube → MeshInstance3D + StandardMaterial3D），挂到 EntityRoot 下。 |
| **运行时投影** | IR 变更后，增量同步到场景树（创建/更新/删除节点），仅负责呈现与物理，无业务逻辑。 |

### 2.2 数据与格式

- **Game IR**：TOON 为主（省 token），JSON 可作备用。初始状态来自 `res://test_data/initial_state.toon`。
- **Patch**：TOON 或 JSON 编码的 patch 数组，通过 `IRManager.apply_patch(patch_string)` 应用。
- **实体类型**：MVP 已支持例如 `cube`（3D 盒子，含 position、color 等）；可扩展。

### 2.3 MCP 桥接（AI 可观测、可操作）

- **Godot 端**：addon `gameclaw_mcp`，autoload `MCPTCPServer`。仅在 debug 或 `GAMECLAW_MCP_ENABLED=1` 时监听；端口 0（系统分配），监听成功后自动更新：
  - Cursor：`~/.cursor/mcp.json`
  - OpenCode：`~/.config/opencode/opencode.json`
- **本机桥**：单文件 Python `gameclaw_mcp.py`（FastMCP），stdio 接 Cursor/Claude，TCP JSON-RPC 接 Godot。依赖：`pip install fastmcp`，无 Node.js/npm/build。

**MCP Tools（与 Godot 方法一一对应）**：

| 类别 | 方法 | 用途 |
|------|------|------|
| IR 状态 | get_ir_state, query_ir_path | 读当前 IR、按路径查询 |
| Patch | apply_patch, get_patch_history, validate_ir, rollback_last | 应用补丁、查历史、校验、回滚 |
| 场景 | inspect_scene_tree, get_entity_node_props | 场景树结构、实体对应节点属性 |
| 感知 | capture_screenshot, capture_viewport, read_godot_log | 截图、视口、引擎日志 |
| 调试 | eval_gdscript, start_frame_probe, read_probe_log, stop_frame_probe | 受限 GDScript 执行、帧级打点 |

### 2.4 开发/发布环境区分

- **开发**：F5 或 Debug 导出时 MCP TCP 默认启用，并自动更新 Cursor/OpenCode 配置。
- **发布**：Release 导出默认不启 MCP；需创作者模式时可设 `GAMECLAW_MCP_ENABLED=1`。

### 2.5 原则与规范（已文档化）

- **PRINCIPLES.md**：Iron Laws 1–10（AI 第一开发者、TOON 省 token、数据与逻辑分离、事务与回滚、可插拔 Codec、多模型路由、安全边界、分层假设/先观察后改/单变量隔离等）。
- **.cursor/rules**：ai-native-principles.mdc、mcp-debug-protocol.mdc，约束 AI 行为与 MCP 排查流程。
- **docs/MCP_DEV_VS_RELEASE.md**：addons 与 gameclaw_mcp.py 的角色、开发/发布差异。

---

## 三、当前范围边界（MVP 内/外）

**已包含**：
- 单场景、基于 TOON 的 IR 加载与 Patch 应用。
- 3D 实体（如 cube）的创建与属性更新（位置、颜色等）。
- 完整 MCP 工具链：状态读取、Patch、场景检查、截图、日志、帧探针、受限 eval。
- 无编辑器拖拽：实体均由 IR + EntityFactory 动态生成。

**明确不包含（留作后续）**：
- 多场景/关卡切换、存档与读档。
- 网络/多人、UGC 发布与 Remix。
- 中心化 AI 推理服务（当前 BYOK/本地 MCP 调用）。
- 复杂物理/碰撞玩法、完整 2D/动画管线。
- 可视化编辑器；创作入口为「IR/Patch + MCP」。

---

## 四、技术栈小结

- **引擎**：Godot 4.6，GDScript，Forward+。
- **序列化**：TOON（主）+ JSON（备），Codec 可插拔。
- **AI 接入**：MCP over stdio（Python gameclaw_mcp.py）→ TCP → Godot addon；Cursor/OpenCode/Claude 等 MCP 主机可用。
- **版本/规范**：PRINCIPLES.md + Cursor Rules 约束设计与排错流程。

---

## 五、建议给「下一步计划评估 AI」的输入

- 将本文档与 **PRINCIPLES.md**、**docs/MCP_DEV_VS_RELEASE.md** 一并提供。
- 说明目标阶段：例如「Phase 2：Public Beta / Remix 裂变」或「增强 AI 自主验收/回归能力」或「首款可对外试玩的 Demo」。
- 约束：继续遵守 Iron Laws；不引入硬编码；新增能力优先通过 IR/Patch + 现有 MCP 能力扩展，再考虑新 MCP 或新进程。
