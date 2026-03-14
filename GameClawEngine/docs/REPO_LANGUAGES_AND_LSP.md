# 仓库语言与 LSP 配置说明

## 仓库语言统计（全仓库）

| 语言       | 扩展名   | 文件数  | 说明           |
|------------|----------|---------|----------------|
| C/C++      | .h/.c/.cpp/.cc | 约 7368 | 引擎与 thirdparty 主体 |
| GDScript   | .gd      | 826     | Godot 脚本     |
| C#         | .cs      | 301     | 引擎 C# 相关   |
| Python     | .py      | 126     | 工具/文档/MCP 等 |
| 场景等     | .tscn 等 | 少量    | Godot 场景/资源 |

**GameClawEngine 子项目**：主要为 `.gd`（约 16 个）+ 少量 `.py`（如 `gameclaw_mcp.py`）、`.tscn`。

---

## 已安装的用户级 LSP（Cursor 扩展）

以下扩展已确认安装在**用户级**（`cursor --list-extensions`）：

| 语言       | 扩展 ID                          | 用途         |
|------------|-----------------------------------|--------------|
| Python     | `anysphere.cursorpyright`         | Pyright LSP  |
| Python     | `ms-python.python`               | Python 支持  |
| C/C++      | `llvm-vs-code-extensions.vscode-clangd` | clangd LSP |
| GDScript   | `geequlim.godot-tools`           | Godot/GDScript |

用户级 `settings.json` 已做如下设置，保证 LSP 生效：

- `python.languageServer": "Default"`：使用默认 Python 语言服务（Cursor 下为 Pyright）。
- `C_Cpp.intelliSenseEngine": "disabled"`：关闭 MS C/C++ IntelliSense，避免与 clangd 冲突，由 clangd 提供 C/C++ 补全与诊断。

---

## 可选：C# 支持（微软扩展在 Cursor 中受限）

仓库中有约 301 个 `.cs` 文件。**注意**：微软的 **C# Dev Kit**（`ms-dotnettools.csdevkit`）和**新版 C/C++ 扩展**在 Cursor 等 VS Code 分支中已被许可限制，会提示仅能在“Microsoft Visual Studio Code、vscode.dev、GitHub Codespaces”中使用，因此**不要在 Cursor 里依赖微软的 C# Dev Kit**。旧版「C#」扩展（`ms-dotnettools.csharp`）也可能被引导到 Dev Kit 或受同样条款影响，不建议在 Cursor 下使用。

**推荐替代**：使用 **DotRush**（基于 Roslyn，支持 IntelliSense、调试、测试等），在 Cursor 中可用：

```bash
cursor --install-extension nromanov.dotrush
```

- 扩展 ID：`nromanov.dotrush`（VS Marketplace）
- 项目：<https://github.com/JaneySprings/DotRush>
- 仅在你需要改引擎 C# 部分时安装即可。

---

## 小结

- **Pyright**、**clangd**、**Godot (GDScript)** 已覆盖当前主要开发语言，且均为用户级安装。
- 用户级配置文件：`%APPDATA%\Cursor\User\settings.json`，上述 LSP 相关项已写入该文件。
