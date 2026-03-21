# 资产入库 SOP（Asset Intake）

**版本**：1.0  
**上级流程**：[`production_sop.md`](production_sop.md)

---

## Iron Law 对齐

- 场景与 IR **只引用 `asset_ref`**（及 schema 允许的逻辑键），与 [`docs/PRINCIPLES.md`](../docs/PRINCIPLES.md) 中数据/逻辑分离一致。  
- Registry 条目是资产可解析性的**证据**；无条目则视为未入库。

---

## 流水线：staging → library → registry

| 阶段 | 含义 | 建议操作 |
|------|------|----------|
| **staging** | 下载包、解压、待审素材暂存区（可不在版本库内） | 校验压缩包哈希、许可文件是否齐全 |
| **library** | 已批准、可复用的工程内资源目录（如 `res://` 下统一子树） | 命名稳定、不随场景改路径 |
| **registry** | `data/asset_registry_draft.json` 中的逻辑登记 | 每条 `asset_ref` 必填字段完整、`approval_status` 明确 |

入库完成判据：**registry 中存在记录 + library 路径可解析**（以当前引擎/工具实现为准）。

---

## Registry 必填字段（合同）

以下字段为**文档层合同**；若实现侧 schema 不同，以实现为准并回写本文档。

| 字段 | 说明 |
|------|------|
| `asset_ref` | 全局稳定 ID；IR 中仅使用此键引用资产。 |
| `local_path` | 工程内可加载路径（相对工程或 `res://` 约定）。 |
| `type` | 资产类型枚举（如 `sprite`、`game_entity`、音频等），与 validator/schema 一致。 |
| `source_url` | 来源 URL 或包标识，可追溯。 |
| `license_type` | 许可类型（如 CC0、CC-BY、专有等）。 |
| `approval_status` | 是否已获准用于本仓库/发行（如 `draft` / `approved`）。 |
| `fallback_color` | 加载失败时的可观测降级（色块/占位），便于 L2 调试。 |

可选扩展：`tags`、`notes`（保持短；大段说明放 `spec/scene_xxx.md`）。

---

## 场景与脚本约束

- **禁止**：在场景 `.tscn`、GDScript、或 IR 中硬编码磁盘绝对路径或随意 `res://` 字符串而不经 `asset_ref`。  
- **允许**：引擎内部解析层根据 registry 将 `asset_ref` 转为路径（实现细节不暴露在 IR 编辑规范中）。

---

## 来源优先级（推荐）

降低许可与风格风险时的**建议**顺序（非强制）：

1. **Kenney** 等明确游戏资产包  
2. **OpenGameArt (OGA)** 等带许可页的资源  
3. **itch.io** 等平台标注 **CC0** 的包  

无论来源，**`source_url` + `license_type` + `approval_status`** 三者须可审计。

---

## 反模式清单

- 先写 `icon_ref` 字符串，后补 registry（或永不补）。  
- 同一份贴图复制多路径，多个 `asset_ref` 指向不同文件（除非刻意做变体并文档说明）。  
- staging 目录直接当 library 长期引用（路径不稳定）。

---

## 与工具链的映射

| 产物 | 用途 |
|------|------|
| `data/asset_registry_draft.json` | 注册表真源；与 [`demo_scope.md`](demo_scope.md) 中 Registry 合同可对照。 |
| `spec/scene_xxx.md` | 列出本场景用到的 `asset_ref`，与 registry 交叉核对。 |

---

## 相关文档

- 总流程：[`production_sop.md`](production_sop.md)  
- 四文件约定：[`scene_template_sop.md`](scene_template_sop.md)  
- 验收：[`acceptance_sop.md`](acceptance_sop.md)  
- Demo 资产表：[`demo_scope.md`](demo_scope.md)  
- 路线图：[`roadmap_alignment.md`](roadmap_alignment.md)
