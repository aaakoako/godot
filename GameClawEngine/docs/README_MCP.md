# GameClawEngine MCP 连接说明

MCP 桥接已轻量化：**单文件 Python**（`gameclaw_mcp.py`）替代原 Node.js 目录，无需 npm/build。

**自检（改完必跑）**：Godot F5 运行后，在项目根执行 `python verify_mcp.py`，退出码 0 即跑通。

## 1. 依赖（一次性）

```bash
pip install -r requirements.txt
# 或: pip install fastmcp
```

## 2. 连接关系

- **Godot**：按 **F5 运行游戏** 后，TCP 服务在 127.0.0.1:&lt;随机端口&gt; 启动，并自动更新以下配置：
  - `%USERPROFILE%\.cursor\mcp.json`（Cursor）
  - `%USERPROFILE%\.config\opencode\opencode.json`（OpenCode）
- **Cursor**：项目内 `.cursor/mcp.json` 已配置 `gameclaw`，command 为 `python gameclaw_mcp.py`，cwd 为 `${workspaceFolder}`（需以 **GameClawEngine** 为工作区根目录打开）。

## 3. 使用步骤

1. 用 Godot 打开 **GameClawEngine** 项目，按 **F5** 运行游戏（控制台会打印端口，并自动更新 Cursor/OpenCode 配置）。
2. 用 Cursor 或 OpenCode 打开工作区。
3. 重启对应 MCP 主机后，`gameclaw` MCP 可用（get_ir_state、apply_patch 等）。

## 4. 开发环境 vs 发布环境

- **开发 / 调试环境**：默认启用 MCP TCP（编辑器 F5 / Debug 运行）。
- **发布给玩家的包**：默认**不**启用 MCP TCP，也不会要求玩家配置 MCP 主机。
- 若后续需要创作者模式或专用发布包，可通过环境变量 `GAMECLAW_MCP_ENABLED=1` 显式开启。

## 5. 常见问题

| 现象 | 处理 |
|------|------|
| MCP 报错 "connect ECONNREFUSED" | 必须先 **F5 运行游戏**，游戏窗口保持打开。 |
| 找不到 gameclaw_mcp 或 ModuleNotFoundError | 在项目根执行 `pip install fastmcp`；确认 Cursor 的 cwd 为 GameClawEngine 根目录（含 gameclaw_mcp.py）。 |
| `verify_mcp.py` 非 0 退出 | 先确认 Godot 已 F5 启动，再在项目根执行 `python verify_mcp.py`；若仍失败，优先检查 Godot 控制台与 `~/.cursor/mcp.json` 中的端口。 |
| 端口/配置 | F5 后 Godot 会自动更新 Cursor 与 OpenCode 配置（`~/.cursor/mcp.json`、`~/.config/opencode/opencode.json`）；若没有更新，优先重启游戏和 MCP 主机。 |
