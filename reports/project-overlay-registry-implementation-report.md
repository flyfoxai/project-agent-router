# Project Overlay Registry 实施报告

- 生成时间：2026-06-26 21:00 CST
- 执行角色：ASK总管（Hermes Agent / Jarvis）
- 目标项目：Multi-Agent Orchestration System
- `project_id`：`multiagent-orchestration-system`
- 业务根：`/Users/hula/workspace/multiagent-orchestration-system`
- Git 根：`/Users/hula/workspace/multiagent-orchestration-system`
- task_guard workspace：`/Users/hula/workspace/multiagent-orchestration-system`
- 本轮性质：人工批准后的 P0 Project Overlay Registry 草案落地与实施报告

## 1. 本轮结论

已按人工批准创建 Project Overlay Registry 草案：

```text
/Users/hula/workspace/multiagent-orchestration-system/config/projects.yaml
```

并输出本实施报告：

```text
/Users/hula/workspace/multiagent-orchestration-system/reports/project-overlay-registry-implementation-report.md
```

本轮只做项目事实层草案与接入规划，不实施 Hermes core 改造、不直接写 Hermes 内部 DB、不迁移 ASK Git、不触发 Gateway 自动派发、不扩大 coder 并发、不执行 merge / commit / push / publish。

## 2. 输入与偏差记录

用户批准要求执行：

```text
/Users/hula/workspace/multiagent-orchestration-system/hermes-tasks/create-project-overlay-registry.md
```

实际预检结果：该文件不存在。已在 `/Users/hula/workspace/multiagent-orchestration-system/hermes-tasks` 搜索 Markdown 任务文件，仅发现：

```text
/Users/hula/workspace/multiagent-orchestration-system/hermes-tasks/post-upgrade-project-management-plan.md
```

因此本轮未伪造任务文件读取结果，而是基于以下真实输入继续：

1. 老板当前飞书批准消息。
2. 既有正式规划报告：`/Users/hula/workspace/multiagent-orchestration-system/reports/post-upgrade-project-management-plan.md`。
3. 既有审计报告：`/Users/hula/workspace/multiagent-orchestration-system/reports/hermes-project-boundary-and-management-audit.md`。
4. ASK 多智能体编排 skill 的项目管理规划参考：`references/ask-post-upgrade-project-management-planning.md`。

## 3. 已创建的 Registry 内容

`config/projects.yaml` 是一个 overlay fact layer，不是 Hermes core 配置，不是数据库迁移，也不包含密钥。

核心字段：

```yaml
registry_version: 1
schema: project-overlay-registry/v1
status: draft
routing_policy:
  default_dispatch_mode: manual
  gateway_auto_dispatch_allowed: false
  coder_concurrency_expansion_allowed: false
  require_project_header_in_reports: true
  require_live_git_root_verification_before_completion: true
projects:
  ask:
    project_id: ask
    business_root: /Users/hula/workspace/ASK
    project_root: /Users/hula/workspace/ASK
    current_git_root: /Users/hula/workspace
    desired_git_root: /Users/hula/workspace/ASK
    git_root_status: needs_migration
  multiagent-orchestration-system:
    project_id: multiagent-orchestration-system
    business_root: /Users/hula/workspace/multiagent-orchestration-system
    project_root: /Users/hula/workspace/multiagent-orchestration-system
    current_git_root: /Users/hula/workspace/multiagent-orchestration-system
    desired_git_root: /Users/hula/workspace/multiagent-orchestration-system
    git_root_status: independent
```

### 3.1 ASK 项目登记

ASK 被登记为业务项目，但明确保留 Git 边界事实：

- 业务根：`/Users/hula/workspace/ASK`
- 当前 Git 根：`/Users/hula/workspace`
- 目标 Git 根：`/Users/hula/workspace/ASK`
- Git 状态：`needs_migration`

这意味着任何 ASK 汇报、验证、task_guard evidence 都必须同时显示业务根与当前 Git 根，避免误以为 ASK 已经是独立 Git 仓库。

### 3.2 multiagent 项目登记

multiagent-orchestration-system 被登记为独立项目：

- 业务根：`/Users/hula/workspace/multiagent-orchestration-system`
- 当前 Git 根：`/Users/hula/workspace/multiagent-orchestration-system`
- 目标 Git 根：`/Users/hula/workspace/multiagent-orchestration-system`
- Git 状态：`independent`

本轮两个目标产物都写在该项目内。

## 4. task_guard 接入规划

短期不改 task_guard 插件或内部 DB，只在 evidence 中强制写入项目三元组：

```text
project_id=<project_id>; workspace_path=<workspace_path>; git_root=<git_root>
```

本轮已使用的目标项目三元组为：

```text
project_id=multiagent-orchestration-system;
workspace_path=/Users/hula/workspace/multiagent-orchestration-system;
git_root=/Users/hula/workspace/multiagent-orchestration-system
```

规划规则：

1. ASK 任务继续使用 `workspace_path=/Users/hula/workspace/ASK`，但 evidence 必须标注 `git_root=/Users/hula/workspace`。
2. multiagent 任务使用独立 `workspace_path=/Users/hula/workspace/multiagent-orchestration-system`。
3. 跨项目任务：ASK ledger 只保留索引指针，目标项目 ledger 保留真实执行状态和验证证据。
4. completed 状态必须包含目标文件回读、live Git status、禁止范围检查证据。

中期可扩展 task_guard schema 或 wrapper，新增：

```json
{
  "project_id": "multiagent-orchestration-system",
  "workspace_path": "/Users/hula/workspace/multiagent-orchestration-system",
  "business_root": "/Users/hula/workspace/multiagent-orchestration-system",
  "git_root": "/Users/hula/workspace/multiagent-orchestration-system",
  "registry_version": 1
}
```

## 5. Reporter / 飞书项目路由接入规划

Reporter 必须在飞书汇报首段显示项目头，建议模板已写入 `config/projects.yaml`：

```text
项目：{display_name}
project_id：{project_id}
业务根：{business_root}
项目根：{project_root}
当前 Git 根：{current_git_root}
目标 Git 根：{desired_git_root}
Git 状态：{git_root_status}
task_guard workspace：{task_guard_workspace}
目标仓库：{target_repository}
验证状态：{verification_status}
```

飞书路由规则：

1. ASK 相关请求仍由 ASK总管作为唯一面对飞书用户的智能体。
2. 其他逻辑角色只作为 delegate_task worker、后台命令、只读复核或顾问，不直接回复飞书用户。
3. Registry 只提供项目头和路由元数据，不自动创建任务、不自动派发 coder。
4. 若消息中无法唯一解析 project_id，应阻塞并要求 ASK总管消歧，不默认落到 ASK 或父级 workspace。

## 6. Gateway dispatcher 接入规划

本轮没有修改 Gateway 代码或配置。Registry 对 Gateway 的规划约束是：

1. 默认 `dispatch.mode=manual`。
2. `gateway_auto_dispatch_allowed=false`。
3. `auto_spawn_coder_allowed=false`。
4. `concurrency_expansion_allowed=false`。
5. 未来如接入 Gateway dispatcher，必须先只读解析 registry，再校验：
   - `project_id` 是否存在；
   - 请求目标路径是否落在 `project_root` / `business_root` 允许范围内；
   - 是否命中 `forbidden_without_separate_approval`；
   - 是否需要人工审批；
   - 是否有 worktree / lock / ledger 证据。

未经新的人工批准，Gateway 不得因为本 registry 自动派发新 coder。

## 7. 明确未执行事项

本轮未执行：

- 未修改 ASK 业务代码。
- 未修改 ASK `.gitignore`。
- 未迁移 ASK `.git`。
- 未修改 Hermes core。
- 未直接写 Hermes 内部 DB。
- 未执行 `git mv` / `git rm` / `git reset` / `git checkout`。
- 未执行 merge / commit / push / publish。
- 未扩大 coder 并发。
- 未触发 Gateway 自动派发新 coder。

## 8. 验证计划与覆盖矩阵

按修复纪律，本轮验证拆成以下链路：

| 链路 | 本轮状态 | 说明 |
| --- | --- | --- |
| 主会话链路 | 已覆盖 | 由 ASK总管在当前会话创建文件、回读文件、执行只读 Git/YAML 检查。 |
| 委托链路 | 不适用 | 本轮禁止扩大 coder 并发，且任务范围很小，不启动 delegate_task worker。 |
| cheap route / 智能路由链路 | 不适用 | 本轮没有修改模型路由或 cheap route 配置。 |
| auxiliary 链路 | 不适用 | 本轮没有调用辅助模型链路；只做本地文件写入与只读验证。 |
| fallback 链路 | 已规划未改造 | Registry 规定汇报与 evidence 必须携带 project_id，未来 fallback 必须保留该字段；本轮未改 Hermes fallback 实现。 |
| 外部接入链路（Feishu / cron / MCP） | Feishu 规划已覆盖，cron/MCP 不适用 | 本轮输出飞书项目头和路由规则；未创建 cron；未修改 MCP。 |

## 9. 验证结果

验证时间：2026-06-26 21:05:17 CST

验证命令性质：只读检查；未执行 `git mv` / `git rm` / `git reset` / `git checkout` / `git merge` / `git commit` / `git push` / `publish`。

### 9.1 文件存在性

```text
EXISTS /Users/hula/workspace/multiagent-orchestration-system/config/projects.yaml
EXISTS /Users/hula/workspace/multiagent-orchestration-system/reports/project-overlay-registry-implementation-report.md
MISSING /Users/hula/workspace/multiagent-orchestration-system/hermes-tasks/create-project-overlay-registry.md
```

结论：两个本轮目标产物均存在；用户批准消息中提到的任务文件仍不存在，已如实记录为输入偏差。

### 9.2 YAML 解析

使用 Ruby Psych 解析 `config/projects.yaml`，结果：

```text
schema=project-overlay-registry/v1
status=draft
projects=ask,multiagent-orchestration-system
ask_git_status=needs_migration
multiagent_git_status=independent
```

结论：YAML 可解析，两个项目均已登记，Git 边界状态符合预期。

### 9.3 Git 根验证

```text
multiagent=/Users/hula/workspace/multiagent-orchestration-system
ask=/Users/hula/workspace
```

结论：multiagent 是独立 Git root；ASK 当前仍归属于父级 `/Users/hula/workspace`，未在本轮迁移。

### 9.4 multiagent 范围状态

```text
?? config/projects.yaml
?? hermes-tasks/post-upgrade-project-management-plan.md
?? reports/hermes-project-boundary-and-management-audit.md
?? reports/post-upgrade-project-management-plan.md
?? reports/project-overlay-registry-implementation-report.md
```

结论：本轮新增目标产物为 `config/projects.yaml` 与 `reports/project-overlay-registry-implementation-report.md`；其余 `hermes-tasks/post-upgrade-project-management-plan.md`、`reports/hermes-project-boundary-and-management-audit.md`、`reports/post-upgrade-project-management-plan.md` 是本轮开始前已存在的未跟踪规划/审计产物。

### 9.5 ASK 禁止范围状态

```text
 M ASK/.gitignore
M  ASK/src/packages/infrastructure/rate-limit/token-bucket.ts
M  ASK/src/packages/infrastructure/security/input-validator.ts
M  ASK/src/packages/infrastructure/security/xss-filter.ts
D  ASK/tests/unit/phase4-security-helpers.test.ts
D  ASK/tests/unit/phase4-token-bucket.test.ts
```

结论：ASK 禁止范围仍为既有 dirty 状态。本轮没有写入 ASK 路径；这些状态仅作为风险背景记录，不归因于本轮 Project Overlay Registry 写入。

### 9.6 覆盖结论

- 主会话链路：通过，目标文件已创建并回读/解析。
- 委托链路：不适用，本轮未启动 delegate_task worker。
- cheap route / 智能路由链路：不适用，本轮未改模型路由。
- auxiliary 链路：不适用，本轮未调用辅助模型。
- fallback 链路：规划已记录，未改造运行链路。
- 外部接入链路：Feishu 汇报规则已写入规划；cron/MCP 未涉及。

总体结论：P0 Project Overlay Registry 草案已落地并完成只读验证；完成状态仅覆盖本轮允许的两个写入产物，不代表 ASK Git root 修复、Gateway 接入或 task_guard schema 改造已完成。

## 10. 后续建议

建议按以下顺序推进，均需独立审批：

1. **P1 task_guard wrapper/schema 接入**：把 registry 中的 project object 显式写入 ledger evidence 或 schema。
2. **P1 Reporter 模板接入**：让飞书汇报统一使用 registry 项目头。
3. **P1 Gateway dispatcher 只读接入**：只读解析 registry，不自动派发 coder。
4. **P2 ASK Git root 修复**：单独冻结窗口、生成回滚方案、人工审批后执行；不与本轮 registry 工作混合。

## 11. 产物路径

```text
/Users/hula/workspace/multiagent-orchestration-system/config/projects.yaml
/Users/hula/workspace/multiagent-orchestration-system/reports/project-overlay-registry-implementation-report.md
```
