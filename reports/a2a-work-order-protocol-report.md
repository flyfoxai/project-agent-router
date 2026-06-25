# ASK A2A Work Order Protocol 落地报告

- report_time: 2026-06-25 12:09:25 CST
- workspace: `/Users/hula/workspace/ASK`
- git_root: `/Users/hula/workspace`
- branch: `chore/speckit-to-sp-migration`
- task_guard_id: `ask-a2a-work-order-protocol-20260625`
- verdict: `COMPLETED_WITH_LOCAL_EVIDENCE`

## 1. 本次落地内容

本次固化 ASK A2A Work Order Protocol，目标是把 ASK 多 Agent 编码协作中的派工、状态同步、交接、审查退回、人工汇报统一为结构化协议。

实际落地范围：

1. 新增协议模板：
   - `/Users/hula/workspace/ASK/.tasks/team-codex/templates/a2a-work-order-protocol.md`
2. 接入当前 Hermes ASK 编排 skill：
   - `/Users/hula/.hermes/skills/software-development/ask-multi-agent-orchestration/SKILL.md`

未修改业务代码、测试、依赖、锁文件或 ESLint 配置。

## 2. 五类标准消息

模板已定义以下五类消息：

1. `WORK_ORDER`：派工消息。
2. `STATUS_UPDATE`：状态同步消息。
3. `HANDOFF`：交接消息。
4. `REVIEW_RESULT`：检查 / 退回消息。
5. `HUMAN_REPORT`：人工负责人汇报消息。

公共协议字段包含：

- `protocol_version: ask-a2a-v1`
- `run_id`
- `task_id`
- actor / assignee / target
- workspace / repo / worktree / branch
- permissions / allowed_files / forbidden_files
- evidence / validation / risks / blockers

## 3. Dispatcher / Lock / Gate 规则

已固化的关键规则：

1. Dispatcher 默认 `dispatch.mode=manual`。
2. Gateway/dispatcher 只有在同时满足以下条件时可拾取任务：
   - `dispatch.mode=auto`
   - `gateway_allowed=true`
   - `WORK_ORDER` 字段完整
   - workspace 是绝对路径
   - 可写任务有 worktree/branch/lock
   - 不触碰禁止文件和共享入口
3. 可写编码任务必须声明 lock；只读审查可不加锁但必须保持只读。
4. 同一文件集不得并发创建多个可写 worker。
5. 编码 worker 完成后必须先发 `STATUS_UPDATE ready_for_review` 或 `HANDOFF needs_review`。
6. 独立验证必须读取任务说明、diff、变更文件、测试结果、禁止文件清单。
7. Review verdict 固定为：
   - `PASS_READY_FOR_HUMAN_MERGE_REVIEW`
   - `REQUEST_CHANGES`
   - `BLOCKED_NEEDS_HUMAN_DECISION`
   - `FAIL_SCOPE_VIOLATION`
   - `FAIL_VALIDATION`
8. 汇报必须区分 verified / unverified / blocked / risk。
9. 完成声明必须有真实文件、diff、日志、命令 exit code 或 ledger 证据。

## 4. Hermes ASK 编排 skill 接入

已在当前 Hermes profile 的 ASK 编排 skill 中加入强制引用：

- 路径：`/Users/hula/.hermes/skills/software-development/ask-multi-agent-orchestration/SKILL.md`
- 位置：`Recent ASK targeted SP review addition`
- 接入内容：当 ASK 多 Agent 需要派发 coding/review/coordinator/reporter worker 时，必须使用 A2A 模板标准化消息；每次 dispatch 或 handoff 必须选择五类消息之一；默认 dispatcher mode 为 manual；可写 worker 需要 scoped files + worktree/branch/lock 或明确 lock 豁免；reviewer verdict 使用固定枚举；面向人工的进度汇报必须区分 verified/unverified/blocked/risk，不能把本地 merge gate 当成 PR/CI 成功。

## 5. 验证证据

### 5.1 模板文件验证

命令结论：

```text
path=/Users/hula/workspace/ASK/.tasks/team-codex/templates/a2a-work-order-protocol.md
exists=True
bytes=11440
lines=313
PASS WORK_ORDER
PASS STATUS_UPDATE
PASS HANDOFF
PASS REVIEW_RESULT
PASS HUMAN_REPORT
PASS protocol_version
PASS dispatcher_manual
PASS gateway_allowed
PASS lock_rule
PASS review_gate
PASS human_report_gate
PASS ledger_path
```

### 5.2 Skill 接入验证

命令结论：

```text
path=/Users/hula/.hermes/skills/software-development/ask-multi-agent-orchestration/SKILL.md
contains_template_ref=True
contains_five_types=True
contains_manual_dispatch=True
contains_lock_gate=True
```

### 5.3 Git 与禁止文件验证

Git 上下文：

```text
root=/Users/hula/workspace
branch=chore/speckit-to-sp-migration
```

模板文件状态：

```text
ASK/.gitignore:13:.tasks/ ASK/.tasks/team-codex/templates/a2a-work-order-protocol.md
!! ASK/.tasks/team-codex/templates/a2a-work-order-protocol.md
```

说明：`.tasks/` 被 ASK 仓库 ignore，模板是本地任务/协作证据文件，不进入当前 Git tracking。

禁止文件状态检查：

```text
--- forbidden package/lock/config status ---
```

上述输出为空，表示本轮未修改：

- `ASK/package.json`
- `ASK/pnpm-lock.yaml`
- `ASK/config/tools/.eslintrc.js`

Phase5 选定文件仍存在既有 dirty 状态：

```text
M  ASK/src/packages/infrastructure/rate-limit/token-bucket.ts
M  ASK/src/packages/infrastructure/security/input-validator.ts
M  ASK/src/packages/infrastructure/security/xss-filter.ts
D  ASK/tests/unit/phase4-security-helpers.test.ts
D  ASK/tests/unit/phase4-token-bucket.test.ts
```

这些是本轮 A2A 之前已存在的 Phase5 工作区状态；本次 A2A 收口未对这些业务代码 / 测试文件执行写入。

## 6. 当前结论

`ASK A2A Work Order Protocol` 已完成本地落地：

- 五类标准消息模板已创建。
- dispatcher / lock / review / report gate 已写入模板。
- 当前 Hermes ASK 编排 skill 已接入模板引用和强制使用规则。
- 未触碰 package / lock / ESLint 配置。
- 未新增业务代码改动。
- `.tasks` 模板受 `.gitignore` 管理，是本地协作证据，不会自动进入 Git commit。

## 7. 后续建议

1. 如果希望该协议进入仓库版本管理，需要单独决策是否调整 `.gitignore` 或把模板移动到已跟踪的文档目录。
2. 下一轮真实多 Agent 编码试点应使用该模板生成 `WORK_ORDER`、`STATUS_UPDATE`、`HANDOFF`、`REVIEW_RESULT`、`HUMAN_REPORT` 实例。
3. 若启用 Gateway 自动拾取，必须显式设置 `dispatch.mode=auto` 且 `gateway_allowed=true`，并先通过 worktree/branch/lock 检查。
4. Phase5 最终分支更新还有独立遗留验证事项，不属于本 A2A 协议落地范围。
