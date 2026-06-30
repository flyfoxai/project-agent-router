# ASK A2A Work Order Protocol

状态：active template
适用范围：ASK 多 Agent 编码、审查、协调、汇报任务
主控角色：ASK总管
状态源：project-task-guard ledger + `.tasks/**` evidence + Kanban/card（如可用）

## 1. 目标

本协议把 ASK 多 Agent 协作中的“派工、状态同步、交接、验收退回、人工汇报”固定为五类标准消息，避免 worker 只靠自由文本交接，降低并行编码时的覆盖、遗漏和假完成风险。

本协议不替代 ASK 现有 SP 规则、task guard、Kanban/card、git worktree、review gate 或人工 merge gate；它只定义 Agent 之间传递信息时必须包含的最小字段。

## 2. 五类标准消息

### 2.1 `WORK_ORDER`：派工消息

由 `ASK总管` 发出。用于启动编码、只读审查、协调、验证或报告 worker。

```yaml
message_type: WORK_ORDER
protocol_version: ask-a2a-v1
run_id: "ask-<date>-<short-slug>"
card_id: "t_xxx | none"
actor: "ASK总管"
assignee: "代码实现智能体 | 独立验证智能体 | Speckit执行智能体 | Gemini顾问智能体 | 调度台账监听器 | 协调Agent名"
role_kind: "coder | reviewer | coordinator | reporter | speckit | advisor | ledger"
project:
  project_id: "ask | multiagent-orchestration-system | blocked"
  display_name: "ASK | Multi-Agent Orchestration System | blocked"
  board: "ask | multiagent-orchestration-system | blocked"
  workspace_path: "<absolute path from config/projects.yaml>"
  current_git_root: "<absolute current_git_root from config/projects.yaml plus live verification>"
  desired_git_root: "<absolute desired_git_root from config/projects.yaml>"
  git_root_status: "needs_migration | independent | blocked"
  dispatch_mode: "manual | blocked"
routing:
  source: "explicit_project_id | explicit_project_alias | board_slug | workspace_path | current_project | default_project | system_meta | blocked_clarification"
  confidence: "high | medium | low | blocked"
  conflict_resolution_order:
    - explicit_project_id
    - explicit_project_alias
    - board_slug
    - workspace_path
    - current_project
    - default_project
    - system_meta
    - blocked_clarification
  requires_clarification: false
target:
  project: ASK
  module: "<module / feature / package>"
  files_allowed:
    - "path/to/file"
  files_forbidden:
    - "package.json"
    - "pnpm-lock.yaml"
    - "src/shared-entry.ts"
workspace:
  repo: "/Users/hula/workspace/ASK"
  worktree: "/Users/hula/worktrees/ASK/<run>/<lane> | none"
  branch: "agent/<assignee>/<slug> | current-readonly"
permissions:
  mode: "readonly | write-scoped | command-scoped"
  allowed_tools:
    - "read_file"
    - "terminal"
  forbidden_tools:
    - "git push"
    - "rm -rf"
locks:
  required: true
  lock_path: ".tasks/.locks/<lock-name>.lock | none"
  conflict_policy: "stop-and-report | read-only-fallback"
dispatch:
  mode: "manual | auto"
  gateway_allowed: false
  active_executor_required: true
  dry_run: "true | false"
  worker_auto_dispatch_triggered: false
  gateway_auto_dispatch_triggered: false
  real_worker_task_created: false
instructions:
  objective: "<one sentence objective>"
  context_refs:
    - "CTX-REF or file path"
  acceptance_criteria:
    - "<measurable condition>"
  verification_commands:
    - "pnpm test -- <focused-test>"
completion_output_required:
  - changed_files
  - commands_with_exit_code
  - risk_notes
  - rollback_notes
  - next_owner
stop_conditions:
  - "scope_conflict"
  - "lock_missing_or_conflict"
  - "destructive_action_needed"
  - "business_decision_needed"
```

#### `WORK_ORDER` gate

- Gateway / Dispatcher 生成任何 `WORK_ORDER` 前必须读取 `config/projects.yaml`，并先完成项目路由、边界校验、阻断判断与 Reporter 项目头回显；不得只靠 shell cwd 推断项目。
- `WORK_ORDER.project` 与 `WORK_ORDER.routing` 是必填块；缺少时不得进入 worker、Kanban、session 或 profile。
- 没有 `files_allowed` 或 `workspace.worktree` 的可写编码任务不得启动。
- `dispatch.mode` 默认必须为 `manual`；只有 ASK总管显式写 `auto` 且 `gateway_allowed=true` 时，Gateway dispatcher 才能拾取。
- P3 dry-run work order 必须设置 `dispatch.dry_run=true`、`worker_auto_dispatch_triggered=false`、`gateway_auto_dispatch_triggered=false`、`real_worker_task_created=false`。
- 可写 worker 必须有 `locks.required=true` 或明确说明为什么不需要锁。
- 没有真实 `session_id`、tmux 窗口、进程 PID、ledger 事件或输出路径时，不得宣称 worker 正在运行。

### 2.2 `STATUS_UPDATE`：状态同步消息

由任一 worker 或调度台账监听器写入。用于同步进展、阻塞、命令结果和下一步。

```yaml
message_type: STATUS_UPDATE
protocol_version: ask-a2a-v1
run_id: "ask-<date>-<short-slug>"
card_id: "t_xxx | none"
actor: "<worker name>"
status: "queued | running | blocked | ready_for_review | changes_requested | done | cancelled | failed"
progress:
  percent: 0
  current_step: "<what is being done>"
  completed:
    - "<verified completed item>"
  next_step: "<next concrete action>"
workspace:
  worktree: "<absolute path | none>"
  branch: "<branch | none>"
evidence:
  command: "<command | none>"
  exit_code: "<int | none>"
  output_path: "<path | none>"
  changed_files:
    - "<path | none>"
blockers:
  - id: "BLOCKER-001"
    type: "dependency | test_failure | conflict | permission | business_decision | tool_failure"
    detail: "<plain language blocker>"
    needs_human: false
handoff_to: "<next actor | ASK总管 | none>"
timestamp: "YYYY-MM-DDTHH:mm:ssZ"
```

#### `STATUS_UPDATE` gate

- `done` 必须带验证命令、exit code、输出路径或文件回读证据。
- `blocked` 必须写清 blocker 类型、原始错误或缺失条件，以及下一步责任人。
- 不允许把子代理口头报告当成 `done`；ASK总管必须回读真实文件、diff、日志或 ledger。

### 2.3 `HANDOFF`：交接消息

用于 worker 之间或 worker 到 ASK总管的交接。尤其适合协调 Agent 与编码 Agent、编码 Agent 与检查 Agent之间。

```yaml
message_type: HANDOFF
protocol_version: ask-a2a-v1
run_id: "ask-<date>-<short-slug>"
from_actor: "<actor>"
to_actor: "<actor>"
reason: "implementation_done | needs_review | needs_fix | needs_coordination | needs_human_decision | resume_after_compaction"
summary: "<short factual summary>"
input_materials:
  - path: "<file/log/report path>"
    purpose: "<why the next actor must read it>"
verified_facts:
  - "<fact backed by evidence>"
open_questions:
  - "<question or none>"
changed_files:
  - "<path | none>"
commands_run:
  - command: "<command>"
    exit_code: 0
    output_path: "<path>"
risks:
  - "<risk or none>"
next_required_action: "<single concrete action>"
forbidden_repeats:
  - "<action not to repeat>"
```

#### `HANDOFF` gate

- 交接必须包含 `input_materials` 与 `next_required_action`；否则下一位 Agent 不得假设自己知道上下文。
- 上一位 Agent 的中间结论必须标注 `verified_facts` 或 `risks`，不能混成笼统总结。
- 上下文压缩恢复时，必须优先使用 `HANDOFF` 重新打开真实文件，不得只凭摘要继续改代码。

### 2.4 `REVIEW_RESULT`：检查 / 退回消息

由 `独立验证智能体` 或 ASK总管发出。用于 review、测试验收、风险检查和退回编码 Agent。

```yaml
message_type: REVIEW_RESULT
protocol_version: ask-a2a-v1
run_id: "ask-<date>-<short-slug>"
reviewer: "独立验证智能体 | ASK总管"
review_target:
  card_id: "t_xxx | none"
  assignee: "<coder/coordinator>"
  worktree: "<absolute path>"
  branch: "<branch>"
  diff_base: "<commit/ref>"
verdict: "PASS_READY_FOR_HUMAN_MERGE_REVIEW | REQUEST_CHANGES | BLOCKED_NEEDS_HUMAN_DECISION | FAIL_SCOPE_VIOLATION | FAIL_VALIDATION"
checks:
  scope:
    result: "pass | fail | blocked"
    evidence: "<path or command>"
  diff:
    result: "pass | fail | blocked"
    evidence: "<path or command>"
  tests:
    result: "pass | fail | blocked"
    evidence: "<path or command>"
  risk:
    result: "pass | fail | blocked"
    evidence: "<notes>"
findings:
  - id: "FINDING-001"
    severity: "blocker | high | medium | low | note"
    owner: "<coder/coordinator/ASK总管/human>"
    file: "<path | none>"
    detail: "<what is wrong>"
    required_fix: "<concrete fix or decision>"
return_to: "<actor | none>"
merge_gate:
  allowed_to_merge: false
  human_approval_required: true
```

#### `REVIEW_RESULT` gate

- `PASS_READY_FOR_HUMAN_MERGE_REVIEW` 不等于已 merge；最终 merge 仍需 ASK总管和人工确认。
- `REQUEST_CHANGES` 必须包含 finding、owner 和 required_fix，编码 Agent 才能接单。
- 发现越权文件、共享配置、锁冲突或禁止文件变更时，必须使用 `FAIL_SCOPE_VIOLATION`，不得让 worker 自行继续扩大修复。

### 2.5 `HUMAN_REPORT`：人工负责人汇报消息

只能由 `ASK总管` 或明确授权的总进度汇报 Agent 生成，用于向老板汇报整体进度、风险、阻塞和下一步。

```yaml
message_type: HUMAN_REPORT
protocol_version: ask-a2a-v1
reporter: "ASK总管 | 总进度汇报Agent"
report_scope: "single_run | batch | project"
run_ids:
  - "ask-<date>-<short-slug>"
project:
  project_id: "ask | multiagent-orchestration-system | blocked"
  display_name: "ASK | Multi-Agent Orchestration System | blocked"
  business_root: "<absolute business root from config/projects.yaml>"
  project_root: "<absolute project root from config/projects.yaml>"
  current_git_root: "<absolute current git root from config/projects.yaml plus live verification>"
  desired_git_root: "<absolute desired git root from config/projects.yaml>"
  git_root_status: "independent | needs_migration | blocked"
  task_guard_workspace: "<absolute task_guard workspace>"
  target_repository: "<absolute target repository>"
  routing_source: "config/projects.yaml"
  routing_basis: "explicit_project_id | alias_match | task_guard_evidence | cwd_git_root | blocked_ambiguous"
  routing_confidence: "high | medium | low | blocked"
  header_required: true
overall_status: "on_track | blocked | needs_decision | ready_for_review | done | risk"
summary:
  conclusion_first: "<project display name + one sentence conclusion>"
  completed:
    - "<completed item>"
  in_progress:
    - "<active item>"
  blocked:
    - "<blocker or none>"
  risks:
    - "<risk or none>"
  next_steps:
    - "<next action>"
verification:
  checked_sources:
    - "config/projects.yaml"
    - "task_guard ledger"
    - ".tasks evidence"
    - "git diff/status"
  commands:
    - command: "<command>"
      exit_code: 0
decisions_needed:
  - id: "DECISION-001"
    background: "<plain language background>"
    recommended_option: "<option>"
    options:
      - "<option>"
```

#### `HUMAN_REPORT` gate

- 面向老板的结论必须先说项目名和结论；`summary.conclusion_first` 必须以前缀 `项目：<display_name>` 或等价项目头开头。
- 生成任何 `HUMAN_REPORT` 前，Reporter 必须先读取 `config/projects.yaml`，并把 `project` 块填充为 registry 中对应项目的真实字段；不得只凭当前工作目录、记忆或上一轮摘要补项目身份。
- 项目查询必须按 `routing_policy.conflict_resolution_order` 执行：优先显式 `project_id`，其次 task_guard evidence、cwd/project root、Git top-level、Hermes profile cwd；命中多个项目、缺少 registry 条目或置信度为 `low` 时，必须设置 `project.project_id=blocked`、`overall_status=needs_decision | blocked`，并在 `decisions_needed` 中请求 ASK总管/老板澄清。
- 项目切换必须由新的 `WORK_ORDER`、`HANDOFF` 或人工指令显式给出目标 `project_id`；切换后必须重新读取 `config/projects.yaml` 并重新验证 `project_root`、`current_git_root`、`target_repository`，不得沿用上一项目的 header。
- 汇报必须区分已验证、未验证、阻塞、风险。
- 不得把局部 focused pass 写成 full pass；不得把本地 merge gate 写成 PR 已打通。

## 3. Dispatcher 规则

1. 新任务默认 `dispatch.mode=manual`。
2. Gateway/dispatcher 只允许拾取同时满足以下条件的任务：
   - `dispatch.mode=auto`
   - `gateway_allowed=true`
   - `WORK_ORDER` 字段完整
   - workspace 是绝对路径
   - 可写任务有 worktree/branch/lock
   - 不触碰禁止文件和共享入口
3. Reviewer/reporter 自动任务必须有绝对 `workspace.worktree` 或 `workspace.repo`，否则应进入 `blocked` 并交回 ASK总管。
4. Dispatcher 不得为同一文件集并发创建多个可写 worker。

## 4. Lock 规则

1. 可写编码任务必须声明 lock；只读审查可不加锁但必须保持只读。
2. lock 最小粒度优先为模块目录或明确文件集，不得用项目根锁替代细粒度锁，除非任务本身是规则入口治理。
3. 发现 lock 冲突时，worker 必须停止写入，发 `STATUS_UPDATE blocked`，由 ASK总管重新拆分或排序。
4. 共享配置、根规则、全局脚本、同一 API route/test 同时只允许一个可写 owner。

## 5. Review / Merge Gate 规则

1. 编码 worker 完成后必须先发 `STATUS_UPDATE ready_for_review` 或 `HANDOFF needs_review`。
2. 独立验证必须读取：任务说明、diff、变更文件、测试结果、禁止文件清单。
3. Review verdict 只能使用：
   - `PASS_READY_FOR_HUMAN_MERGE_REVIEW`
   - `REQUEST_CHANGES`
   - `BLOCKED_NEEDS_HUMAN_DECISION`
   - `FAIL_SCOPE_VIOLATION`
   - `FAIL_VALIDATION`
4. Merge 前至少需要：scope check、diff check、focused tests、风险说明、人工确认。
5. 无 Git remote 时不得声称 PR 已创建或 CI 已通过；只能说本地 merge gate 状态。

## 6. 推荐落盘位置

```text
.tasks/team-codex/templates/a2a-work-order-protocol.md      # 本协议与模板
.tasks/team-codex/assignments/TASK_ASSIGNMENT_*.md          # WORK_ORDER 实例
.tasks/<run>/dispatch-table.md                              # 本轮派工表
.tasks/<run>/status/*.md                                    # STATUS_UPDATE 实例
.tasks/<run>/handoff/*.md                                   # HANDOFF 实例
.tasks/<run>/review/*.md                                    # REVIEW_RESULT 实例
.tasks/<run>/report.md                                      # HUMAN_REPORT / 收口报告
/Users/hula/.hermes/task_guard/tasks.json                   # 跨上下文任务状态 ledger
```

## 7. 最小合规检查清单

- [ ] 五类消息之一已明确标注 `message_type`。
- [ ] `run_id`、actor、assignee/target、workspace、权限、允许/禁止文件齐全。
- [ ] 可写任务有独立 worktree/branch 或明确的非并发文件边界。
- [ ] 可写任务有 lock 或明确的 lock 豁免理由。
- [ ] Dispatcher 默认 manual；auto 必须显式写明。
- [ ] Review verdict 使用固定枚举。
- [ ] 汇报区分 verified / unverified / blocked / risk。
- [ ] 完成声明有真实文件、diff、日志、命令 exit code 或 ledger 证据。
