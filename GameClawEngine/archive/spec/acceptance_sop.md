# 验收与 Checkpoint SOP（Acceptance）

**版本**：1.0  
**上级流程**：[`production_sop.md`](production_sop.md)

---

## Iron Law 对齐

- 验收证据须可指向 **IR → Patch → 状态 → 投影** 中的一层或多层，与 [`docs/PRINCIPLES.md`](../docs/PRINCIPLES.md) 及 Debug 分层一致。  
- 文档层 `scene_xxx_acceptance.json` 与引擎 **`acceptance_spec`** / **Golden 回归** 对齐：声明检查项，实现以代码为准。

---

## 三级定义：L1 / L2 / L3

| 等级 | 定义 | 典型检查 |
|------|------|----------|
| **L1 结构** | IR/schema 合法、必备实体存在、Patch 可应用、关键谓词可观测 | Validator 通过、`verify_outcome` 类结构断言、无阻断加载错误 |
| **L2 表现** | 投影与绑定符合合同；可见反馈与 `asset_ref` 解析正确 | 精灵/占位/fallback 行为符合 registry、UI 与事件外吐可观测 |
| **L3 发布** | 可重复自动化验证、许可与 registry 完整、与 Golden 基线一致 | `regression_runner.py` 绿灯、CI 通过、文档与数据无已知 P0 |

**规则**：无 L1 不要求 L2/L3；无 L2 不宣称「可演示给外部」；**仅 L3 可打基线标签**（checkpoint）。

---

## `scene_xxx_acceptance.json` 与引擎关系

- **文档合同**：列出本场景验收 ID、依赖的初始 IR 路径、期望结果摘要、对应 L 等级。  
- **引擎 `acceptance_spec`**：运行时或测试侧消费的结构化验收规格（见 Phase 1.5A 相关实现与 [`roadmap_alignment.md`](roadmap_alignment.md)）。  
- **Golden regression**：仓库级黄金用例与 `regression_runner.py` 参数（如 `--initial-ir`）应与 acceptance 文档互相引用，避免「只写在 markdown」无法执行。

对齐方式建议：

- 在 `scene_xxx_acceptance.json` 中保留 `initial_ir`、`golden_doc_ref`（如 `docs/C1_GOLDEN_CASE.md`）、`regression_cmd` 等键（具体键名以实现/模板为准，先合同后代码）。

---

## Checkpoint 条件

- **仅当** 本切片达到 **L3**，且 Golden / 回归在约定 IR 下 **exit 0**，方可：  
  - 打 git 标签或写入「基线」说明；  
  - 在 [`roadmap_alignment.md`](roadmap_alignment.md) 或 sprint 文档中登记为完成检查点。  
- L1/L2 可合并请求内自检，**不**作为长期基线锚点。

---

## 工具与参考

| 资源 | 说明 |
|------|------|
| [`regression_runner.py`](../regression_runner.py) | 回归入口；`--initial-ir` 指向 `data/scene_xxx_init.toon` 等。 |
| [`docs/C1_GOLDEN_CASE.md`](../docs/C1_GOLDEN_CASE.md) | Golden Case 制度化示例模式。 |
| `GAMECLAW_INITIAL_IR_PATH` | 与冒烟/验收共用初始 IR。 |

---

## 反模式清单

- 仅人工「看一眼」通过即标 L3，无自动化或无可重复命令行。  
- acceptance JSON 与 `acceptance_spec` 字段长期漂移无人同步。  
- 在 L2 未稳时接入真实 LLM 并同时改表现层（调试面爆炸，见 roadmap 说明）。

---

## 相关文档

- 总流程八步与第 8 步 checkpoint：[`production_sop.md`](production_sop.md)  
- 四文件中的 acceptance 文件：[`scene_template_sop.md`](scene_template_sop.md)  
- 资产与 L2：`asset_intake_sop.md`  
- 竖切片范围：[`demo_scope.md`](demo_scope.md)  
- Phase 2 重排：[`roadmap_alignment.md`](roadmap_alignment.md)
