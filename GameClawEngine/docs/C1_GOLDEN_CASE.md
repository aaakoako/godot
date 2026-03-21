# C.1 Golden Case: Attack Dummy

**版本**：1.0.0  
**创建日期**：2026-03-14  
**状态**：冻结（Frozen）

---

## 修改流程

此文档一旦通过评审即为冻结基线。如需变更：

1. 提 PR，标题注明 `[GOLDEN CASE CHANGE]`
2. 必须同步更新以下所有文件：
   - `docs/C1_GOLDEN_CASE.md`（本文档）
   - `test_data/sprint_c1_init.toon`（若初始状态变更）
   - `validation/orchestrator/verify_c1_ui_e2e.py`（终态断言、输入序列；`orchestrator/` 保留兼容入口）
   - `tooling/regression_runner.py`（若接口变更；根目录 `regression_runner.py` 为兼容入口）
   - `.github/workflows/c1_golden.yml`（若环境/命令变更）
3. 变更后必须本地通过 `python regression_runner.py --repeat 3`

> **禁止静默漂移**：任何断言、输入序列、初始状态的改变，若未同步上述所有文件，视为违反 Golden Case 制度，PR 不得合入。

---

## 场景描述

单按钮攻击史莱姆。验证完整闭环：

```
UI 事件流出 → 外部决策（Mock Orchestrator）→ TOON/JSON Patch 注入 → 引擎验收 / 回滚
```

---

## 环境要求

| 项目 | 要求 |
|------|------|
| Godot 版本 | `GameClawEngine/` 目录下的 `Godot_*_console.exe`（版本由文件名确定，不得随意升级） |
| Python 版本 | ≥ 3.11 |
| Python 依赖 | `fastmcp>=1.0`（见 `requirements.txt`） |
| 操作系统 | Windows 10/11 x64（本地）；`windows-latest`（CI） |
| GODOT_PORT | 由 Godot 启动后写入 `~/.cursor/mcp.json`，Python 脚本自动读取 |
| 初始 IR 路径 | `res://test_data/sprint_c1_init.toon` |

---

## 初始状态（`sprint_c1_init.toon`）

| 实体 | 字段 | 初始值 |
|------|------|--------|
| `enemy` | `type` | `combat_dummy` |
| `enemy` | `hp` | `3` |
| `enemy` | `alive` | `true` |
| `lbl_enemy_hp` | `type` | `label` |
| `lbl_enemy_hp` | `text` | `"Enemy HP: 3"` |
| `lbl_message` | `type` | `label` |
| `lbl_message` | `text` | `"A slime appears."` |
| `btn_attack` | `type` | `button` |
| `btn_attack` | `text` | `"Attack!"` |

---

## 输入序列

```
ui_click(entity_id="btn_attack", count=4, interval_ms=120)
```

- 4 次连续点击，间隔 120ms
- 前 3 次命中存活敌人（hp: 3→2→1→0，第 3 次触发死亡）
- 第 4 次点击敌人已死

---

## 终态断言

| 路径 | 预期值 | 说明 |
|------|--------|------|
| `/entities/enemy/hp` | `0` | 三次命中后归零 |
| `/entities/enemy/alive` | `false` | 死亡后设为 false |
| `/entities/lbl_message/text` | `"It's already dead!"` | 第 4 次点击触发规则 B |

---

## 非法 Patch 断言（DoD 5）

向引擎发送以下非法 patch：
```json
{"ops": [{"op": "replace", "path": "/entities/nonexistent_entity/foo", "value": 1}]}
```

预期响应必须满足：
- HTTP/RPC 层级返回 `error` 字段（非 `result`）
- `error.data.layer` 非空
- 游戏状态未被污染（IR 不包含 `nonexistent_entity`）

---

## DoD 覆盖状态

| DoD | 内容 | 自动化覆盖 |
|-----|------|-----------|
| DoD 1 | 双端启动（Godot + Python 无报错） | 自动（`python regression_runner.py` 兼容入口，实际执行 `tooling/regression_runner.py`） |
| DoD 2 | 第一击：hp 3→2，lbl 更新 | 自动（终态断言覆盖最终值，中间状态由 orchestrator 日志记录） |
| DoD 3 | 击杀：hp=0, alive=false | 自动（终态断言） |
| DoD 4 | 鞭尸：message="It's already dead!" | 自动（终态断言） |
| DoD 5 | 非法 patch 返回 error + layer + evidence_path | 自动（`python orchestrator/mock_orchestrator.py --test-illegal` 兼容入口，实际执行 `validation/orchestrator/mock_orchestrator.py`） |
| DoD 6 | 测试后环境恢复 | 自动（`python orchestrator/verify_c1_ui_e2e.py` 兼容入口，进程级隔离：通过 `GAMECLAW_INITIAL_IR_PATH` 注入 C.1 初始态，不改写 `project.godot`） |

---

## 运行命令

### 本地单次
```bash
cd GameClawEngine
python regression_runner.py
```

### 本地稳定性验证（3 次连跑）
```bash
python regression_runner.py --repeat 3
```

### CI 模式
```bash
python regression_runner.py --repeat 1 --ci
```

输出结果写入 `artifacts/c1_golden_summary.json`；每轮日志写入 `artifacts/run_NNN/e2e_godot.log` 与 `artifacts/run_NNN/e2e_orchestrator.log`。

---

## 相关文件

| 文件 | 说明 |
|------|------|
| `test_data/sprint_c1_init.toon` | 初始世界状态（冻结） |
| `validation/orchestrator/verify_c1_ui_e2e.py` | E2E 测试执行主体（`orchestrator/` 提供兼容入口） |
| `validation/orchestrator/mock_orchestrator.py` | 外部决策主循环（硬编码规则；`orchestrator/` 提供兼容入口） |
| `tooling/regression_runner.py` | 回归执行主体（根目录 `regression_runner.py` 为兼容入口） |
| `.github/workflows/c1_golden.yml` | CI workflow |
