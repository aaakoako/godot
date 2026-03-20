# Phase 2 重排说明

**日期**：2026-03-14
**状态**：冻结

---

## 当前阶段状态

| 阶段 | 状态 | 关键资产 |
|------|------|----------|
| Phase 0 原则与架构定型 | ✅ 完成 | IR 唯一事实源、Data/Logic 分离、Patch Transaction、Evidence-driven |
| Phase 1 IR / Patch / 投影底座 | ✅ 完成 | IRManager、PatchEngine、IRValidator、EntityFactory、TOON/JSON Codec |
| Phase 1.5A 验收闭环与回滚 | ✅ 完成 | acceptance_spec、verify_outcome()、自动回滚、evidence bundle |
| Phase 1.5B 最小 UI 与事件外吐 | ✅ 完成 | label、button、combat_dummy、EventOutbox、get_event_log |
| Phase 1.5C C.1 最小玩法闭环 | ✅ 完成 | sprint_c1_init.toon、mock_orchestrator、真 UI 点击全链路自动化 |
| Phase 1.5D Golden Case 制度化 | ✅ 完成 | C1_GOLDEN_CASE.md、regression_runner.py、CI workflow |

**核心事实**：IR → Patch → 投影 → 验收/回滚 → 事件外吐这套工程骨架已验证可信。

---

## Phase 2 重排理由

原路线图将"真实 LLM 接入（Phase 2A）"列为优先。但经过分析：

- 核心语义闭环已稳定，但"可见表现层"尚未成为稳定产品面
- 直接在无稳定投影层时接入真实 AI，调试面会同时膨胀到语义、推理、资产、绑定、运行时五层
- 应当先让投影层可见并硬化，再让真实 AI 驱动同一闭环

**结论**：Phase 2 走正确顺序：**先可见化硬化，再真实 AI 接入**。

---

## Phase 2 分支定义

### Phase 2B — 可见化硬化（立刻执行）

把资产 sourcing、registry 和 presentation binding 固化，让 Godot 投影层第一次稳定落地。

**目标**：最小可见竖切片，6 个 Sacred assets：

| asset_ref | 描述 |
|-----------|------|
| `hero_idle_basic` | 英雄待机 |
| `enemy_idle_basic` | 敌人待机 |
| `proj_fireball_basic` | 火球投射物 |
| `hud_panel_min` | 最小 HUD 面板 |
| `status_poison_icon` | 中毒状态图标 |
| `status_burn_icon` | 燃烧状态图标 |

**核心架构**：

```
IR (Single Source of Truth)
  → Registry (asset_ref → local_path)
  → Presentation Bindings (entity_id → visual_property)
  → Godot SceneTree (runtime projection)
```

**禁止引入**：动画系统、复杂 UI、战斗系统、随机数、回合制、背包、任务系统。

---

### Phase 2A — 真实 AI 接入（延后）

把 `mock_orchestrator.py` 的硬编码决策替换为真实大模型输出。接口提前保留，但等到 Phase 2B 稳定后再接入。

**要做的事**（预研，不实现）：

- prompt 结构化（输出 TOON patch + acceptance_spec）
- Provider Router 接入
- evidence-driven retry 策略
- 超时、预算、重试策略

---

### Phase 2C — 复杂 UI / Gameplay / Infra（继续延期）

| 延期项 | 原因 |
|--------|------|
| `panel`、Container 布局、响应式 UI | Phase 2B 只需要最小 HUD |
| 多敌人、回合制、技能、随机数 | 等 Phase 2B + 2A 稳定后再说 |
| 多模型路由、自主修复、长时记忆 | Phase 2A 之后 |
| 远程 MCP server、多客户端并发 | Infra 延期 |

---

## Phase 2B 禁止项（红线）

1. 不实现 `panel`、Container、响应式布局
2. 不实现动画系统
3. 不实现战斗规则（Phase 1.5C 的 mock orchestrator 除外）
4. 不实现多敌人、回合制、技能、随机数
5. 不实现背包、存档、任务系统
6. 不让运行时逻辑绕过 registry 直接硬编码 NodePath
7. 不实现远程 MCP server 或多客户端并发
8. 不实现多模型路由或云端协作

---

## Phase 2B 执行顺序（预排）

1. 创建 `data/asset_registry_draft.json` — 6 个 Sacred assets 的草稿合同
2. 创建 `data/presentation_bindings.json` — entity_id → visual_property 绑定合同
3. 扩展 `EntityFactory` 支持 sprite 类型
4. 实现 asset_ref → local_path 的 registry 解析路径
5. 扩展 `IRManager` / `UIController` 支持 sprite 投影
6. 用 `regression_runner.py` 验证投影层渲染正确
7. 接入真实图片资源（Kenney → OpenGameArt → itch.io CC0 顺序）
