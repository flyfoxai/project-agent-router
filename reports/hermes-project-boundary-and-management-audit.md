# Hermes / ASK / Multi-Agent 项目边界与管理机制审计报告

- 审计时间：2026-06-26 10:22 CST
- 报告路径：`/Users/hula/workspace/multiagent-orchestration-system/reports/hermes-project-boundary-and-management-audit.md`
- 审计角色：ASK总管（Hermes Agent）
- 审计范围：ASK 项目、multiagent-orchestration-system 项目、父级 workspace、Hermes default/profile 配置、Kanban / task_guard / dashboard / gateway 相关能力证据。
- 审计方式：只读采集文件、Git 边界、Hermes 配置非敏字段、SQLite schema、task_guard ledger 结构与关键源码命中；本报告为唯一目标产物。

## 1. 结论摘要

当前环境中，“项目边界”主要由 **Git 仓库顶层、Hermes profile 的 `terminal.cwd`、task_guard 的 workspace key、Kanban task 的 `workspace_path` / board / tenant 字段**共同隐式表达；尚未发现统一的 Hermes `project_id` / `project_registry` / `project_root` 管理层。

关键结论：

1. **ASK 并不是独立 Git 仓库顶层**：`/Users/hula/workspace/ASK` 的 Git top-level 是 `/Users/hula/workspace`，`.git` common dir 为 `../.git`。
2. **multiagent-orchestration-system 是独立 Git 仓库**：`/Users/hula/workspace/multiagent-orchestration-system` 的 Git top-level 与 common dir 均在自身目录内。
3. **Hermes default 与 ASK 相关 profiles 当前都指向 ASK cwd**：default `terminal.cwd=/Users/hula/workspace/ASK`；多个 `ask-*` profile 同样指向 ASK。
4. **Hermes 配置中未发现统一 project registry 字段**：非敏扫描显示 default/profile 配置未命中 `project_registry`、`project_id`、`worktree_base` 等统一边界字段。
5. **Kanban 支持 workspace / board 维度，但不是严格 project registry**：`tasks` 表包含 `workspace_path`、`tenant`、`dispatch_mode`、`session_id` 等字段；但没有 `project_id` 字段。源码中 `kanban_db.py` 对 `workspace` / `board` 命中很多，对 `project_id` 为 0。
6. **task_guard 当前只登记了 `/Users/hula/workspace` 与 `/Users/hula/workspace/ASK`**：未发现 `/Users/hula/workspace/multiagent-orchestration-system` 独立 task_guard project key。
7. **多 Agent 项目与 ASK 项目在文件系统和 Git 上边界清晰，但在 Hermes 管理层没有统一注册关系**：这会导致“同属一个业务体系”和“独立仓库产物”两种视角并存，需要显式管理规则避免误派工、误验证、误归档。

## 2. 已采集证据

### 2.1 Git 边界

只读采集结果：

| 名称 | 路径 | Git top-level | Git common dir | 结论 |
| --- | --- | --- | --- | --- |
| ASK | `/Users/hula/workspace/ASK` | `/Users/hula/workspace` | `../.git` | ASK 是父级 workspace Git 仓库内的子目录，不是独立 Git 根。 |
| workspace | `/Users/hula/workspace` | `/Users/hula/workspace` | `.git` | 父级 workspace 是 Git 根。 |
| multiagent | `/Users/hula/workspace/multiagent-orchestration-system` | `/Users/hula/workspace/multiagent-orchestration-system` | `.git` | multiagent 是独立 Git 仓库。 |

管理含义：

- 对 ASK 的 `git status` / commit / diff 应在 `/Users/hula/workspace` 或其子目录执行，但实际版本边界是父级 workspace。
- 对 multiagent 的报告、文档、代码变更应在 `/Users/hula/workspace/multiagent-orchestration-system` 独立验证。
- 如果 ASK 总管同时处理 ASK 与 multiagent，必须在任务说明里明确“业务项目”和“Git 仓库项目”分别是什么。

### 2.2 Hermes default 配置摘要

只读采集的非敏字段：

```json
{
  "terminal.cwd": "/Users/hula/workspace/ASK",
  "model.default": "gpt-5.5",
  "model.provider": "llmhubapp",
  "plugins.enabled": ["project-task-guard", "provider-stability-guard"],
  "has_project_registry_terms": false
}
```

结论：

- 当前 Jarvis / default Hermes 运行态面向 ASK 工作目录。
- 插件层启用了 `project-task-guard` 和 `provider-stability-guard`。
- 未在 default 配置中发现显式 project registry / project id 管理字段。

### 2.3 ASK profiles 配置摘要

采集到的 profiles：

| profile | terminal.cwd | plugins.enabled | `project_id` | `project_root` | `worktree_base` |
| --- | --- | --- | --- | --- | --- |
| ask-coder-api | `/Users/hula/workspace/ASK` | project-task-guard, provider-stability-guard | false | false | false |
| ask-coder-tests | `/Users/hula/workspace/ASK` | project-task-guard, provider-stability-guard | false | false | false |
| ask-coder-ui | `/Users/hula/workspace/ASK` | project-task-guard, provider-stability-guard | false | false | false |
| ask-coord-contracts | `/Users/hula/workspace/ASK` | project-task-guard, provider-stability-guard | false | false | false |
| ask-orchestrator | `/Users/hula/workspace/ASK` | project-task-guard, provider-stability-guard | false | false | false |
| ask-reporter | `/Users/hula/workspace/ASK` | project-task-guard, provider-stability-guard | false | false | false |
| ask-reviewer-quality | `/Users/hula/workspace/ASK` | project-task-guard, provider-stability-guard | false | false | false |
| ask-reviewer-security | `/Users/hula/workspace/ASK` | project-task-guard, provider-stability-guard | false | false | false |

结论：

- 这些 profiles 是 ASK 专用角色配置，而不是跨项目统一注册表。
- profiles 可以表达“执行角色”和默认工作目录，但不能单独证明项目边界。
- 如果未来要让 multiagent-orchestration-system 也进入 Hermes 管理，应创建独立 profile 或显式 project registry，不能复用 ASK cwd 作为默认边界。

### 2.4 Kanban DB / Dashboard / Gateway 证据

Kanban DB 关键表字段：

```text
kanban_notify_subs: task_id, platform, chat_id, thread_id, user_id, notifier_profile, created_at, last_event_id

task_events: id, task_id, run_id, kind, payload, created_at

task_runs: id, task_id, profile, step_key, status, claim_lock, claim_expires, worker_pid, max_runtime_seconds, last_heartbeat_at, started_at, ended_at, outcome, summary, metadata, error

tasks: id, title, body, assignee, status, priority, created_by, created_at, started_at, completed_at, workspace_kind, workspace_path, branch_name, claim_lock, claim_expires, tenant, result, idempotency_key, consecutive_failures, worker_pid, last_failure_error, max_runtime_seconds, last_heartbeat_at, current_run_id, workflow_template_id, current_step_key, skills, model_override, max_retries, session_id, goal_mode, goal_max_turns, dispatch_mode
```

关键源码命中摘要：

| 文件 | `project_id` | `project_root` | `workspace` | `board/board_slug` | `dispatch` | 说明 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `hermes_cli/kanban_db.py` | 0 | 0 | 174 | 367 | 133 | Kanban 核心以 workspace / board / dispatch 等概念组织任务。 |
| `plugins/kanban/dashboard/plugin_api.py` | 0 | 0 | 6 | 352 | 18 | Dashboard 插件直接封装 `kanban_db`；注释说明 CLI、gateway `/kanban`、dashboard 共享写路径。 |
| `hermes_cli/gateway.py` | 0 | 17 | 2 | 18 | 21 | gateway 存在 project_root 相关处理，但不是统一 registry。 |
| `gateway/session.py` | 0 | 0 | 1 | 0 | 0 | session 侧主要是消息上下文字段，不承担项目注册。 |

Dashboard 插件注释证据要点：

- `/api/plugins/kanban/` 是 dashboard plugin API。
- 每个 handler 是 `hermes_cli.kanban_db` 的薄封装或直接 SQL 查询。
- 写入路径与 CLI、gateway `/kanban` 命令共享，避免三端漂移。
- `/events` WebSocket 通过 `task_events` 表尾随更新。

结论：

- Hermes Kanban 已具备“按 workspace / board / profile / run”管理多任务的能力。
- 但当前 schema 不是 project registry 设计；`workspace_path` 更像执行上下文，`board` 更像看板视图，`tenant` 更像租户/隔离字段。
- 如果要表达“ASK、multiagent、父级 workspace 是三个可治理项目”，需要新增显式 project registry 或在现有 workspace/board 语义上制定硬规则。

### 2.5 task_guard ledger 证据

只读采集结果：

```json
{
  "top_keys": ["projects", "version"],
  "project_keys": ["/Users/hula/workspace", "/Users/hula/workspace/ASK"]
}
```

具体 workspace key：

| workspace key | 是否存在 | task_count | 说明 |
| --- | --- | ---: | --- |
| `/Users/hula/workspace/ASK` | true | 257 | ASK 当前主要任务 ledger。 |
| `/Users/hula/workspace` | true | 0 | 父级 workspace 已登记但无任务。 |
| `/Users/hula/workspace/multiagent-orchestration-system` | false | 0 | multiagent 独立仓库尚未作为 task_guard 项目登记。 |

结论：

- task_guard 当前对 ASK 有强绑定，对 multiagent 没有独立任务状态。
- 这解释了为什么本次任务的执行台账在 ASK workspace 下，而产物写入 multiagent 仓库。
- 后续如果 multiagent 要长期纳入 Hermes 管理，应为其建立独立 task_guard workspace key，避免所有跨项目动作都挂在 ASK ledger 下。

### 2.6 multiagent-orchestration-system 项目状态

只读采集摘要：

```json
{
  "exists": true,
  "has_AGENTS": false,
  "has_git_dir": true,
  "has_reports_dir": true
}
```

结论：

- multiagent 项目是存在且独立的 Git 项目。
- 其本地没有发现项目级 `AGENTS.md`，因此当前报告编写主要遵循 ASK/Hermes 当前会话规则和通用 Markdown 报告约定。
- `reports/` 目录存在，适合放置本报告。

## 3. 边界风险分析

### 3.1 风险一：业务项目边界与 Git 仓库边界不一致

ASK 的业务边界是 `/Users/hula/workspace/ASK`，但 Git 边界是 `/Users/hula/workspace`。这会造成：

- `git status` 可能看到 ASK 外的父级 workspace 变更。
- 提交 ASK 变更时可能误包含其他 workspace 子目录文件。
- task_guard 以 `/Users/hula/workspace/ASK` 记录任务，但 Git evidence 需要解释为父级仓库证据。

建议：

- ASK 任务最终验收时同时注明：业务目录为 `/Users/hula/workspace/ASK`，Git 根为 `/Users/hula/workspace`。
- 自动化脚本中不要假设 cwd 就是 Git 根；应显式执行 `git rev-parse --show-toplevel`。

### 3.2 风险二：multiagent 项目是独立仓库，但当前任务 ledger 挂在 ASK 下

本次报告产物位于独立仓库 `/Users/hula/workspace/multiagent-orchestration-system`，但任务状态在 ASK task_guard 中。这会造成：

- 日后按 multiagent 项目检索任务时可能找不到本次执行记录。
- ASK ledger 中会混入跨项目管理任务。
- “仅报告文件变更”的验证必须切换到 multiagent 仓库，而不能只看 ASK 状态。

建议：

- 为 multiagent 项目初始化独立 task_guard workspace key。
- 跨项目任务在 ASK ledger 中只保留索引指针，实际产物验证写入目标项目 ledger。

### 3.3 风险三：Hermes profiles 表达角色，不表达项目注册

ASK profiles 都指向 `/Users/hula/workspace/ASK`。这适合 ASK 多智能体，但如果未来复用到 multiagent，会导致：

- Worker 默认 cwd 错误。
- 报告、测试、日志写入错误项目。
- “ASK总管”角色误以为所有任务都属于 ASK。

建议：

- 为 multiagent 建立独立 profile，例如 `multiagent-orchestrator`、`multiagent-reporter`。
- profile 命名中包含项目名，`terminal.cwd` 指向真实项目根。
- 不要用 ASK profile 执行 multiagent 写操作，除非任务明确声明“ASK 管理 multiagent 产物”。

### 3.4 风险四：Kanban board/workspace/tenant 可以承载项目视图，但缺少唯一 project_id

Kanban 现有字段足以追踪任务执行上下文，但无法强制表达唯一项目身份。可能风险：

- 同一 `workspace_path` 与多个 board 的关系不明确。
- board 名称变更可能影响项目视图连续性。
- tenant、workspace、profile 三者之间没有统一约束。

建议：

- 短期：制定命名规则：`board_slug = project_slug`，`workspace_path = project_root`，`tenant = owner_or_org`。
- 中期：增加 project registry 文件或 DB 表，字段至少包括 `project_id`、`display_name`、`project_root`、`git_root`、`default_profile`、`default_board`、`task_guard_workspace`、`owner_channel`。
- 长期：Kanban tasks 关联 `project_id`，Dashboard 和 gateway 统一从 project registry 解析项目上下文。

## 4. 建议的项目管理模型

### 4.1 三层边界模型

建议 Hermes 在 ASK / multiagent 场景下采用三层边界：

1. **业务边界（Business Project）**
   - 例：ASK、multiagent orchestration。
   - 用于需求、PRD、roadmap、用户沟通。

2. **代码边界（Repository / Git Root）**
   - 例：ASK 的 Git root 是 `/Users/hula/workspace`；multiagent 的 Git root 是自身目录。
   - 用于 diff、commit、CI、验证命令。

3. **执行边界（Hermes Execution Context）**
   - 例：profile、cwd、task_guard workspace、Kanban board、worker 权限。
   - 用于派工、恢复、后台任务、工具权限。

任何跨项目任务都应显式列出这三层，避免“业务上属于 ASK 管理，但文件写在 multiagent 仓库”这种情况被误判。

### 4.2 推荐 project registry 草案

可新增一个轻量 registry，例如：

```yaml
projects:
  ask:
    display_name: ASK
    business_root: /Users/hula/workspace/ASK
    git_root: /Users/hula/workspace
    default_profile: ask-orchestrator
    default_board: ask
    task_guard_workspace: /Users/hula/workspace/ASK
    owner_channel: feishu:oc_ee1b2aacf08072f0d1c3618adfb3a0b4

  multiagent-orchestration-system:
    display_name: Multi-Agent Orchestration System
    business_root: /Users/hula/workspace/multiagent-orchestration-system
    git_root: /Users/hula/workspace/multiagent-orchestration-system
    default_profile: multiagent-orchestrator
    default_board: multiagent-orchestration-system
    task_guard_workspace: /Users/hula/workspace/multiagent-orchestration-system
    owner_channel: feishu:oc_ee1b2aacf08072f0d1c3618adfb3a0b4
```

这个 registry 不必一次性深度改造 Hermes；短期可作为只读约定，逐步接入 Kanban / task_guard / dashboard。

### 4.3 推荐派工规则

跨 ASK 与 multiagent 的任务建议使用以下派工表字段：

| 字段 | 含义 |
| --- | --- |
| 业务项目 | 用户目标属于哪个业务系统。 |
| 目标仓库 | 文件实际写入哪个 Git root。 |
| task_guard workspace | 状态记录写入哪个 ledger key。 |
| Hermes profile | 用哪个 profile / cwd 执行。 |
| Kanban board | 卡片/事件写入哪个 board。 |
| 允许文件 | Worker 可写范围。 |
| 禁止文件 | 禁止跨界修改的路径。 |
| 验证命令 | 在目标 Git root 下执行的验证命令。 |

## 5. 本次报告产物验证要求

本次任务的目标产物是：

```text
/Users/hula/workspace/multiagent-orchestration-system/reports/hermes-project-boundary-and-management-audit.md
```

验证标准：

1. 目标文件存在。
2. `multiagent-orchestration-system` Git 仓库中只有该 Markdown 报告文件新增或修改。
3. 不修改 ASK 源码、Hermes 源码、配置文件、Kanban DB、业务代码。
4. task_guard ledger 更新只作为执行状态记录，不属于目标仓库产物。

## 6. 后续行动建议

优先级 P0：

- 明确 ASK 与 multiagent 的三层边界：业务边界、Git 边界、Hermes 执行边界。
- 对跨项目任务，强制在派工表中写明目标仓库和验证仓库。

优先级 P1：

- 为 `/Users/hula/workspace/multiagent-orchestration-system` 建立独立 task_guard workspace key。
- 为 multiagent 建立独立 Hermes profile，避免复用 ASK cwd。
- 在 Kanban 中约定 board slug 与项目 slug 一致。

优先级 P2：

- 增加 Hermes project registry 轻量配置。
- Dashboard / gateway / task_guard 从 registry 解析项目上下文。
- 在跨项目报告、调度台账、Feishu 汇报中统一展示 project_id / git_root / task_guard_workspace。

## 7. 审计限制

- 本次未修改 Hermes 源码或配置，只做只读采集与报告写入。
- 本次未执行数据库迁移、profile 创建或 project registry 创建。
- 本次源码命中统计用于定位设计现状，不等价于完整静态分析。
- 本报告基于 2026-06-26 当前本机环境；后续配置变更可能改变结论。
