# MCP 自检与跑通 — AI 可执行清单

本文档供 AI 或人在修改 MCP/Godot 后自检：**先跑通再交差**，符合 AI Native（自己改、自己验）。

---

## 1. 一步到位自检（推荐）

在 **GameClawEngine** 项目根目录执行：

```bash
# 1) 确保 Python 依赖已装
pip install -r requirements.txt

# 2) 在 Godot 里按 F5 运行游戏，保持窗口不关；控制台应出现：
#    [MCP TCP] Listening on 127.0.0.1:PORT
#    [MCP TCP] Updated global Cursor MCP config with GODOT_PORT=PORT
#    [MCP TCP] Updated OpenCode MCP config with GODOT_PORT=PORT

# 3) 本机自检（会读 ~/.cursor/mcp.json 里的 GODOT_PORT，或设环境变量 GODOT_PORT=端口）
python verify_mcp.py
```

- **退出码 0**：ping 与 get_ir_state 均成功，MCP 链路通。
- **非 0**：看 stderr 输出，按下面「常见失败」排查。

---

## 2. 常见失败与处理

| 现象 | 处理 |
|------|------|
| `GODOT_PORT not set and not found in ~/.cursor/mcp.json` | 先在本机 Godot 里 **F5 运行游戏**，再执行 `verify_mcp.py`；或手动设置 `GODOT_PORT=<控制台显示的端口>`。若使用 OpenCode，也可检查 `~/.config/opencode/opencode.json` 中 `mcp.gameclaw.environment.GODOT_PORT`。 |
| `ping failed: Connection refused` / `timed out` | Godot 未运行或未监听：用 Godot 打开 **GameClawEngine** 项目，按 **F5**，确认控制台有 `[MCP TCP] Listening`。 |
| `get_ir_state failed: IRManager autoload not found` | 确认 `project.godot` 的 `[autoload]` 中有 `IRManager`；重新 F5 运行。 |
| `get_ir_state failed: Internal error` | 多为 handler 返回了失败但未带 `error` 字段（已加兜底）。**重启 Godot 并再次 F5** 以加载最新代码后重跑 `verify_mcp.py`。若仍失败，查 Godot 控制台是否有脚本报错。 |
| `get_ir_state missing .state` | Godot 返回格式异常；查 Godot 控制台与 `addons/gameclaw_mcp/handlers/ir_handler.gd` 中 `_handle_get_ir_state` 的返回值。 |

---

## 3. MCP 主机里使用（自检通过后）

1. 使用 Cursor 时：
   - 工作区根为 **Godot**，确保存在 **`Godot/.cursor/mcp.json`**，且 `cwd` 为 `"${workspaceFolder}/GameClawEngine"`（或绝对路径指向 GameClawEngine 根目录）。
2. 使用 OpenCode 时：
   - 确认 `~/.config/opencode/opencode.json` 中存在 `mcp.gameclaw`，且 `command` 指向 `python + gameclaw_mcp.py` 绝对路径。
3. **完全重启对应 MCP 主机**，使配置生效。
4. 在对话中调用 `get_ir_state` 或 `apply_patch`，确认能拿到结果、无 ECONNREFUSED。

---

## 4. AI 自改自验流程（建议）

1. 修改任何 MCP 相关或 Godot 端 handler 后，在 **GameClawEngine** 根目录执行 `python verify_mcp.py`。
2. 若 Godot 未运行：提示「请先在 Godot 中 F5 运行游戏后再执行 verify_mcp.py」。
3. 若 verify 失败：根据退出码与 stderr 按上表排查，修代码或配置后再次 F5 + verify，直到退出码 0。
4. 交差前确保：**verify_mcp.py 退出码 0**，且（若在 MCP 主机中验证）工具调用无连接错误。

这样即可做到 **自己改、自己验、跑通再收尾**，符合 AI Native 的闭环。
