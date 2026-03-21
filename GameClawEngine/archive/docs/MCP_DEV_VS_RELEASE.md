# MCP：addons 与 gameclaw_mcp.py 区别 / 开发与发布环境

## 一、谁用 MCP？

| 角色 | 需要 MCP？ | 说明 |
|------|------------|------|
| **我们（开发/调试）** | 是 | 用 MCP 主机（Cursor / OpenCode）+ gameclaw_mcp.py 连上游戏，做 AI 辅助开发、验收、排查。 |
| **平台创作者（UGC）** | 视产品定 | 若提供「创作者工作台」且用 MCP 驱动，可给创作者用；通常要单独配置，不依赖特定 MCP 主机。 |
| **最终玩家** | 否 | 只玩游戏，不连 Cursor、不跑 gameclaw_mcp.py；发布包默认不开放 MCP 端口。 |

所以：**MCP 是「开发/创作工具链」的一环，不是玩家运行时的一部分**。发布给玩家的包要区分「开发环境」和「发布环境」。

---

## 二、addons/gameclaw_mcp 和 gameclaw_mcp.py 各是什么？

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Cursor / OpenCode / Claude Desktop / 其他 MCP 主机（仅开发/创作环境）      │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ stdio
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  gameclaw_mcp.py（单文件 Python）                                         │
│  · 跑在开发者/创作者本机，被 MCP 主机拉起（python gameclaw_mcp.py）           │
│  · 通过 stdio 和 MCP 主机通信，通过 TCP 和 Godot 游戏通信                   │
│  · 把 MCP 的 get_ir_state、apply_patch 等「翻译」成对 Godot 的 JSON-RPC   │
│  · 不随游戏发布，只随仓库给「开发/创作人员」使用；依赖 pip install fastmcp      │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ TCP (127.0.0.1:随机端口)
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  addons/gameclaw_mcp（Godot 插件 + 游戏内 autoload）                       │
│  · 跑在「正在运行的游戏进程」里                                             │
│  · TCP 服务端：监听端口、收 JSON-RPC、调 IRManager/场景/截图等              │
│  · 只有「开发/调试」或显式开启时才监听（见下）                                │
└─────────────────────────────────────────────────────────────────────────┘
```

|  | addons/gameclaw_mcp | gameclaw_mcp.py |
|--|---------------------|-----------------|
| **是什么** | Godot 里的 TCP 服务端 + 命令分发 + 各 handler | 本机的 MCP 协议适配层（stdio ↔ TCP），单文件 |
| **跑在哪** | 游戏进程内（F5 或导出的可执行文件） | 开发者本机，由 MCP 主机（Cursor/OpenCode）启动 |
| **给谁用** | 任何能连 TCP 的客户端（当前是 gameclaw_mcp.py） | 给 MCP 主机（Cursor / OpenCode / Claude 等）用 |
| **是否随游戏发布** | 代码随项目走；**是否监听端口**由「开发/发布」控制 | 不随游戏发布，只随仓库给开发者用 |

一句话：**addons** = 游戏里的「能力提供方」（IR、Patch、场景、截图等）；**gameclaw_mcp.py** = 把 MCP 主机请求转成对游戏 TCP 调用的「适配层」，只在开发/创作环境用。

---

## 三、开发环境 vs 发布环境

### 1. 行为差异

|  | 开发环境 | 发布环境（玩家包） |
|--|----------|--------------------|
| **何时启用 MCP TCP** | 默认启用（编辑器里 F5、或 Debug 导出） | 默认**不**启用 |
| **依据** | `OS.has_feature("debug")` 为 true | `OS.has_feature("debug")` 为 false |
| **覆盖** | 无需覆盖 | 若要做「创作者模式」发布包，可设环境变量 `GAMECLAW_MCP_ENABLED=1` 再导出，则同样会起 TCP |
| **写主机配置** | 启用时会更新 `%USERPROFILE%\.cursor\mcp.json`（Cursor）与 `%USERPROFILE%\.config\opencode\opencode.json`（OpenCode） | 不启用则不监听、不写文件 |

### 2. 代码逻辑（tcp_server.gd）

- 仅在 **`_should_enable_mcp()` 为 true** 时：
  - 监听 TCP（端口 0）
  - 更新 MCP 主机配置（Cursor 全局 mcp.json + OpenCode opencode.json，command: python, args: 绝对路径 gameclaw_mcp.py）
- `_should_enable_mcp()` 为 true 当且仅当：
  - `OS.get_environment("GAMECLAW_MCP_ENABLED") == "1"`，或
  - `OS.has_feature("debug") == true`（编辑器运行、Debug 导出为 true；Release 导出为 false）。

因此：**默认只有开发/调试时才会起 MCP、更新主机配置；发布给玩家的包不会监听 MCP 端口**。若将来有「给创作者的 Release 包」，可通过设置 `GAMECLAW_MCP_ENABLED=1` 再导出，保留 MCP 能力。

### 3. 和 MCP 主机的关系

- **只有开发环境**需要 MCP 主机（如 Cursor/OpenCode）以及本机的 gameclaw_mcp.py。
- **发布环境**不需要 MCP 主机；玩家也不跑 gameclaw_mcp.py、不配置 MCP 主机文件。

---

## 四、小结

- **addons/gameclaw_mcp**：游戏内 MCP 能力（TCP + 命令实现），随项目存在；**是否监听**由开发/发布和可选环境变量控制。
- **gameclaw_mcp.py**：给 MCP 主机用的 MCP 适配进程（单文件 Python，`pip install fastmcp`），只给「开发/创作」使用，不随游戏发布。
- **开发环境**：默认启用 MCP TCP + 自动更新主机配置（Cursor/OpenCode）；**发布环境**：默认不启用；需要时可凭 `GAMECLAW_MCP_ENABLED=1` 在导出包中启用（例如创作者专用包）。
