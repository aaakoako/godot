# 场景模板 SOP（Scene Template）

**版本**：1.0  
**上级流程**：[`production_sop.md`](production_sop.md)

---

## Iron Law 对齐

- 模板只约束**数据面**（IR 形状、必备实体、命名）；不新增「在投影层写逻辑」的借口。  
- 与 [`docs/PRINCIPLES.md`](../docs/PRINCIPLES.md) 一致：变更仍须走 Patch；模板不豁免。

---

## 三模板概览

| 模板 ID | 目标 | 最小实体集（示例性） | 禁止项 |
|---------|------|----------------------|--------|
| `combat_slice` | 战斗/遭遇竖切片：单位、投射物、最小 HUD | 至少 1 可交互敌对或木桩、1 玩家侧实体、可选 HUD/状态图标 | 把胜负规则写死在场景脚本而非 IR/Patch |
| `dialogue_slice` | 对话/叙事竖切片：说话人、文本承载 | 至少 1 对话锚点实体或 UI 承载、`presentation` 或等价展示字段按 schema | 长段剧情文本硬编码在 `.tscn` 而无 IR 侧引用键 |
| `hub_slice` | 枢纽/选关：入口、导航 | 至少 1 hub 根实体或菜单承载、跳转目标以 IR 可枚举为准 | hub 上直接写死外部 URL 或路径字符串（应经 registry / 配置键） |

具体字段名以当前 **IR schema / validator** 为准；上表为**角色**描述，非引擎强制枚举。

---

## 每场景固定四文件（命名约定）

以下路径均相对 `GameClawEngine/`（或仓库约定的 `data/`、`spec/` 根）。

| 文件 | 职责 |
|------|------|
| `spec/scene_xxx.md` | 人类/策划可读：目标、模板 ID、asset_ref 列表、验收等级目标、已知限制。 |
| `data/scene_xxx_init.toon` | 场景初始 IR（TOON）；**唯一**初始状态源，供 `GAMECLAW_INITIAL_IR_PATH` 或工具链引用。 |
| `data/scene_xxx_bindings.json` | 展示绑定合同：如 `asset_ref` → 精灵/主题键等（结构与项目内 `presentation_bindings.json` 策略对齐时可并列演进）。 |
| `data/scene_xxx_acceptance.json` | 本场景验收声明：等级、检查项、与 Golden 的映射（见 [`acceptance_sop.md`](acceptance_sop.md)）。 |

`xxx` 建议与切片 ID 一致（如 `combat_slice`、`sprint_c1`），避免歧义。

---

## Bindings：合同先行

- `scene_xxx_bindings.json` 可先作为**团队合同**存在：文档与工具约定字段含义与扩展方式。  
- 与现有 **`presentation_bindings.json`** 相同策略：**引擎可不强制依赖**；未实现消费方时不得假装已绑定。  
- IR 中仍只使用 **`asset_ref`** 等逻辑键；bindings 是投影层的补充合同，不替代 registry。

---

## 反模式清单

- 四文件不同步（例如只改 TOON 不改 `scene_xxx.md` 的 asset 列表）。  
- 把 `bindings` 当成第二份 registry，重复填 `local_path`（路径归属 registry，见 [`asset_intake_sop.md`](asset_intake_sop.md)）。  
- 选用 `combat_slice` 却在文档中写满对话分支且无对应 `dialogue_slice` 或拆分说明。

---

## 相关文档

- 总流程八步：[`production_sop.md`](production_sop.md)  
- 资产入库：[`asset_intake_sop.md`](asset_intake_sop.md)  
- 验收：[`acceptance_sop.md`](acceptance_sop.md)  
- 竖切片资产表示例：[`demo_scope.md`](demo_scope.md)  
- 路线图：[`roadmap_alignment.md`](roadmap_alignment.md)
