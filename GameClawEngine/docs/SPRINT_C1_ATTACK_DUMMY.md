# Sprint C.1: Attack Dummy 最小玩法闭环

## 目标

建立第一个外部硬编码游戏主循环（Mock Orchestrator），验证闭环：

**UI 事件流出 → 外部决策 → TOON/JSON Patch 注入 → 引擎验收 / 回滚**

## 玩法

- **名称**: Attack Dummy / 单按钮攻击史莱姆
- **玩家动作**: 点击按钮 `btn_attack`
- **世界状态**: `enemy.hp`、`enemy.alive`、`lbl_enemy_hp.text`、`lbl_message.text`

## 文件与配置

| 路径 | 说明 |
|------|------|
| `test_data/sprint_c1_init.toon` | C.1 初始世界状态（TOON） |
| `orchestrator/mock_orchestrator.py` | 外部主循环（硬编码规则，无 LLM） |
| `scripts/autoload/event_outbox.gd` | 事件队列，MCP `get_event_log` 读取 |
| `addons/gameclaw_mcp/handlers/event_handler.gd` | MCP `get_event_log` 处理 |

**使用 C.1 初始状态**：在 `project.godot` 中设置：

```ini
[application]
config/initial_ir_path="res://test_data/sprint_c1_init.toon"
```

恢复默认 MVP 时改回：

```ini
config/initial_ir_path="res://test_data/initial_state.toon"
```

## 运行方式

1. **启动 Godot**：打开项目，将 `config/initial_ir_path` 设为 `res://test_data/sprint_c1_init.toon`，按 F5 运行主场景（或使用 `launch_godot.py`）。
2. **启动 Mock Orchestrator**：在项目根或 GameClawEngine 目录下执行  
   `python orchestrator/mock_orchestrator.py`  
   （依赖 Godot 已启动且 MCP TCP 已监听，端口由 Godot 写入 `~/.cursor/mcp.json` 的 `GODOT_PORT`。）

## 验收标准（DoD）

| DoD | 内容 | 验证方法 |
|-----|------|----------|
| **DoD 1** | 双端启动 | Godot 加载 `sprint_c1_init.toon`，Python 轮询无报错 |
| **DoD 2** | 第一击 | 点一次 Attack! → enemy.hp 3→2，lbl 与 message 更新，Python 打印成功 |
| **DoD 3** | 击杀 | 再点两次 → hp=0，alive=false，"The slime is defeated!" |
| **DoD 4** | 鞭尸 | 敌人死后再点 → message "It's already dead!"，状态不变 |
| **DoD 5** | 回滚免疫 | 非法 patch 返回 JSON-RPC error，含 `error.data.layer`、`error.data.evidence_path`，状态未污染。运行：`python orchestrator/mock_orchestrator.py --test-illegal` |
| **DoD 6** | 环境恢复 | 测试后将 `config/initial_ir_path` 改回 `initial_state.toon` 或保留 C.1 路径按需切换 |

## 规则摘要

- **规则 A（敌人存活）**：`enemy.alive == true` 时，hp-1，更新 lbl_enemy_hp 与 lbl_message；hp 归零时设 `alive = false`，文案 "The slime is defeated!"。
- **规则 B（敌人已死）**：`enemy.alive == false` 时，仅更新 `lbl_message.text = "It's already dead!"`。

## 红线（本 Sprint 禁止）

- 接入真实 LLM API
- 在 Godot 内写业务状态推进
- 绕过 acceptance_spec / evidence bundle
- 破坏 JSON-RPC 2.0 的 result/error 互斥
