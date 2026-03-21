# Demo Scope: Phase 2B Visible Slice

## 目标

建立 `IR -> Registry -> Presentation -> Godot Projection` 的最小可见闭环。

## 竖切片范围

| asset_ref | 类型 | 描述 |
|-----------|------|------|
| hero_idle_basic | game_entity | 英雄，待机状态 |
| enemy_idle_basic | game_entity | 敌人，待机状态 |
| proj_fireball_basic | sprite | 火球投射物 |
| hud_panel_min | sprite | 最小 HUD 面板背景 |
| status_poison_icon | sprite | 中毒状态图标 |
| status_burn_icon | sprite | 燃烧状态图标 |

## IR 结构

- `hero` / `enemy`：game_entity 类型，含 `presentation.icon_ref` 和 `transform_2d.position`
- `hud_panel`：sprite 类型，含 `icon_ref` 和 `position`/`size`
- `proj_fireball_basic`：sprite 类型

## Registry 合同

`data/asset_registry_draft.json` 定义 `asset_ref -> local_path + fallback_color`。

## Presentation Bindings

`data/presentation_bindings.json` 定义 `entity_id -> icon_ref`（引擎暂不强制依赖）。

## 禁止项

- 动画系统
- 战斗规则
- 多敌人
- 回合制
- 背包/存档/任务
- 多模型路由
- 远程 MCP

## Phase 2B 执行顺序

1. Registry + sprite 投影链路
2. 替换真实 Kenney 图片资源
3. fireball 投射物投影
4. status icon 投影

## 资产来源优先级

1. Kenney Game Assets（CC0）— 首选
2. OpenGameArt（许可明确）— 补
3. itch.io（CC0 / royalty-free）— 兜底

---

## 相关：制作 SOP

本竖切片可作为 `combat_slice` 模板实例引用，完整生产线见：

- [`production_sop.md`](production_sop.md)（总流程）
- [`scene_template_sop.md`](scene_template_sop.md)（四文件约定）
- [`asset_intake_sop.md`](asset_intake_sop.md)（registry）
- [`acceptance_sop.md`](acceptance_sop.md)（L1/L2/L3）
