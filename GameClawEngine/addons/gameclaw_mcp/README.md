# GameClaw MCP（addons 端）

本插件是 **Godot 内的 MCP 能力端**：在游戏进程里提供 TCP 服务，接收 JSON-RPC，执行 IR/场景/截图等操作。  
**和 `tooling/gameclaw_mcp.py`（单文件 Python 桥）的区别、开发/发布环境** 见：`docs/README_MCP.md`（根目录 `gameclaw_mcp.py` 为兼容入口）。

## 开发环境下的行为

- **仅开发/调试时监听**：在编辑器里 F5 或 Debug 导出时，autoload 会监听；**Release 导出给玩家的包默认不监听**（可通过环境变量 `GAMECLAW_MCP_ENABLED=1` 显式开启，例如创作者模式包）。
- **TCP**：使用**端口 0** 由系统分配可用端口。
- **自动写 MCP 主机配置**：监听成功后，会更新：
  - Cursor：`%USERPROFILE%/.cursor/mcp.json`
  - OpenCode：`%USERPROFILE%/.config/opencode/opencode.json`
  并同步 `GODOT_PORT` 与 `tooling/gameclaw_mcp.py` 路径（根目录 `gameclaw_mcp.py` 保留兼容入口）。

## 在 Godot 里看到本插件

1. 用 Godot 打开 **GameClawEngine** 项目（`GameClawEngine/project.godot`）。
2. **Project → Project Settings → Plugins** 中应有 **GameClaw MCP** 且已启用。

## 使用步骤（开发时）

- F5 跑游戏，确认控制台出现 `Listening on ...` 与配置更新日志。
- 重启你正在使用的 MCP 主机（Cursor/OpenCode）。
- 具体连接/排障步骤见 `../../docs/README_MCP.md`（已整合自检与开发/发布说明）。
