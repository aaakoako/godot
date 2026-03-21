# 制作总流程 SOP（Production）

**版本**：1.0  
**范围**：新建场景 / 竖切片时的固定顺序；与 IR、registry、验收机制对齐。首版以文档为主，不强制引擎实现未列能力。

---

## Iron Law 对齐

与 [`docs/PRINCIPLES.md`](../docs/PRINCIPLES.md) 一致处必须遵守：

| 原则 | 制作侧含义 |
|------|------------|
| IR 唯一事实源 | 场景状态、实体定义以 TOON（或经 Codec 的等价 IR）为准，不以编辑器手改节点为准。 |
| Godot 仅投影 | 运行时只渲染与物理；业务逻辑不在 GDScript 里「拍脑袋」决定。 |
| 变更走 Patch | 状态演进经 Patch 事务；禁止为赶进度直接改节点属性当长期方案。 |

---

## 三层分工

| 层 | 职责 | 主要产出 |
|----|------|----------|
| **策划层** | 定义切片目标、验收等级、asset_ref 清单草案 | `spec/scene_xxx.md`、验收等级勾选（见 [`acceptance_sop.md`](acceptance_sop.md)） |
| **制作层** | 选模板、入库资产、写初始 IR、绑定合同、跑通投影 | 四件套（见 [`scene_template_sop.md`](scene_template_sop.md)）、registry（见 [`asset_intake_sop.md`](asset_intake_sop.md)） |
| **验收层** | L1/L2/L3 分级检查、Golden / 回归、checkpoint | `scene_xxx_acceptance.json`、[`regression_runner.py`](../regression_runner.py)、[`docs/C1_GOLDEN_CASE.md`](../docs/C1_GOLDEN_CASE.md) |

---

## 八步标准流程

按顺序执行；跳步须书面记录理由（否则视为流程债务）。

1. **定义规格**：在 `spec/scene_xxx.md` 写清目标实体、交互边界、验收等级目标（L1 起）。  
2. **选模板**：从 `combat_slice` / `dialogue_slice` / `hub_slice` 选一（见 [`scene_template_sop.md`](scene_template_sop.md)）。  
3. **声明 asset_ref**：列出本场景所需 `asset_ref`（可与 [`demo_scope.md`](demo_scope.md) 中 `combat_slice` 示例对照）。  
4. **Intake**：staging → library → 写入 `data/asset_registry_draft.json`（见 [`asset_intake_sop.md`](asset_intake_sop.md)）。  
5. **写 IR**：`data/scene_xxx_init.toon` 仅引用 registry 中已有 `asset_ref`，不硬编码磁盘路径。  
6. **投影**：引擎 / 工具链从 IR + registry 投影到 Godot；绑定见 `scene_xxx_bindings.json`（可为合同先行）。  
7. **冒烟**：能加载、无阻断错误、核心路径可走通（与所选 L 等级一致）。  
8. **Checkpoint**：仅当达到 **L3** 且 Golden/回归通过时，方可打基线标签（见 [`acceptance_sop.md`](acceptance_sop.md)）。

---

## IR / Registry / 投影 职责边界（一句话）

| 组件 | 负责 | 不负责 |
|------|------|--------|
| **IR（TOON）** | 实体与状态、对 `asset_ref` 的逻辑引用 | 解析磁盘路径、下载资源、UI 皮肤细节未在 schema 内者 |
| **Registry** | `asset_ref` → 可加载元数据（路径、类型、许可等） | 游戏规则、战斗结算 |
| **Godot 投影** | 按 IR + registry 呈现与输入/物理 | 作为唯一事实源保存设计意图 |

---

## 与工具链的映射（文字）

| 环境 / 工具 | 用途 |
|-------------|------|
| `GAMECLAW_INITIAL_IR_PATH` | 指定启动时加载的初始 IR 文件（如某 `scene_xxx_init.toon`）。 |
| `data/asset_registry_draft.json` | 资产注册表；场景侧只认 `asset_ref`。 |
| `python regression_runner.py --initial-ir <path>` | 以指定 IR 跑 Golden / 回归（与 [`docs/C1_GOLDEN_CASE.md`](../docs/C1_GOLDEN_CASE.md) 模式一致）。 |

---

## 反模式清单

- 边搭场景边找图、边改 IR 边补 registry（顺序颠倒，难复盘）。  
- 在场景或脚本里拖资源 / 写死 `res://...` 或绝对路径，绕过 `asset_ref`。  
- 无 registry 条目的 `icon_ref` / 任意字符串当资源 ID。  
- 无 L1（结构可验证）就要求 L3（发布级）或打基线标签。

---

## 相关文档

- Phase 2B 竖切片示例：[`demo_scope.md`](demo_scope.md)  
- Phase 2 重排与阶段状态：[`roadmap_alignment.md`](roadmap_alignment.md)  
- 场景模板与四文件：[`scene_template_sop.md`](scene_template_sop.md)  
- 资产入库：[`asset_intake_sop.md`](asset_intake_sop.md)  
- 验收与 checkpoint：[`acceptance_sop.md`](acceptance_sop.md)
