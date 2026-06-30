# P3 Gateway Dispatcher Project Overlay Registry Routing Report

项目：Multi-Agent Orchestration System  
project_id：multiagent-orchestration-system  
workspace_path：/Users/hula/workspace/multiagent-orchestration-system  
git_root：/Users/hula/workspace/multiagent-orchestration-system  
生成时间：2026-06-29T11:42:24+08:00

## 1. 结论

P3 已完成为 **dry-run Gateway / Dispatcher 项目路由接入层**：在 multiagent-orchestration-system 仓库内固化了 Gateway 必读 `config/projects.yaml` 的 gate 模板，扩展了 A2A `WORK_ORDER` 项目与 routing metadata，新增了 dry-run Gateway project router 包装入口，并用验证脚本真实调用 router 覆盖 8 个 P3 用例。

本轮没有接入 Hermes core 运行时、没有写 Hermes 内部 DB、没有创建真实 worker、没有写 Kanban task、没有 push/merge/publish/commit。P4 应处理 Feishu 项目对话状态、命令接入和真实运行时拦截。

## 2. Required fields

```text
P3_GATEWAY_REGISTRY_READ_READY=YES
P3_PROJECT_ID_REQUIRED_READY=YES
P3_ROUTING_PRIORITY_READY=YES
P3_TASK_METADATA_PROJECT_FIELDS_READY=YES
P3_KANBAN_A2A_PROJECT_FIELDS_READY=YES
P3_WORKSPACE_CONTAINER_BLOCK_READY=YES
P3_LOW_CONFIDENCE_CLARIFICATION_READY=YES
P3_ASK_HIGH_RISK_ACTION_BLOCK_READY=YES
P3_REPORTER_PROJECT_ECHO_READY=YES
P3_DRY_RUN_WORK_ORDER_READY=YES
P3_VALIDATION_PASSED=YES
WORKER_AUTO_DISPATCH_TRIGGERED=NO
GATEWAY_AUTO_DISPATCH_TRIGGERED=NO
ASK_GIT_ROOT_MIGRATION_EXECUTED=NO
ASK_CODE_MODIFIED=NO
HERMES_CORE_MODIFIED=NO
PUSH_EXECUTED=NO
MERGE_EXECUTED=NO
PUBLISH_EXECUTED=NO
```

## 3. 本轮变更范围

新增/修改文件：

- `templates/gateway-project-routing-gate.md`
  - 固化 Gateway/Dispatcher registry 必读、project_id 解析优先级、字段校验、阻断规则、ASK 特例、父级 workspace 阻断、Reporter 项目头、dry-run 禁止自动派发。
- `templates/a2a-work-order-protocol.md`
  - `WORK_ORDER` 增加 `project` 与 `routing` 字段。
  - `dispatch` 增加 `dry_run`、`worker_auto_dispatch_triggered=false`、`gateway_auto_dispatch_triggered=false`、`real_worker_task_created=false`。
- `scripts/gateway/project-router.rb`
  - 新增 dry-run Gateway project router 包装入口。
  - 读取 `config/projects.yaml`，按 P3 优先级解析项目，输出 JSON route/block/reporter header/dry-run work order metadata。
  - 阻断场景返回 exit=10；不创建 worker，不写 Kanban，不派发。
- `scripts/validation/verify-gateway-project-routing.rb`
  - 新增 P3 验证脚本，真实调用 `scripts/gateway/project-router.rb` 覆盖 8 个用例。
- `reports/p3-gateway-project-routing-report.md`
  - 本报告。

## 4. Registry 验证

- `config/projects.yaml` YAML 可解析：YES
- registry projects：projects=ask,multiagent-orchestration-system
- required projects present：`ask`, `multiagent-orchestration-system`
- ASK：`current_git_root=/Users/hula/workspace`，`desired_git_root=/Users/hula/workspace/ASK`，`git_root_status=needs_migration`
- multiagent-orchestration-system：`current_git_root=/Users/hula/workspace/multiagent-orchestration-system`，`git_root_status=independent`

## 5. P3 验证结果

命令：

```bash
ruby scripts/validation/verify-gateway-project-routing.rb
```

结果：

```text
P3_VALIDATION_EXIT=0
summary.total=22
summary.passed=22
summary.failed=0
```

P3 flags：

```json
{
  "P3_GATEWAY_REGISTRY_READ_READY": "YES",
  "P3_PROJECT_ID_REQUIRED_READY": "YES",
  "P3_ROUTING_PRIORITY_READY": "YES",
  "P3_TASK_METADATA_PROJECT_FIELDS_READY": "YES",
  "P3_KANBAN_A2A_PROJECT_FIELDS_READY": "YES",
  "P3_WORKSPACE_CONTAINER_BLOCK_READY": "YES",
  "P3_LOW_CONFIDENCE_CLARIFICATION_READY": "YES",
  "P3_ASK_HIGH_RISK_ACTION_BLOCK_READY": "YES",
  "P3_REPORTER_PROJECT_ECHO_READY": "YES",
  "P3_DRY_RUN_WORK_ORDER_READY": "YES",
  "P3_VALIDATION_PASSED": "YES",
  "WORKER_AUTO_DISPATCH_TRIGGERED": "NO",
  "GATEWAY_AUTO_DISPATCH_TRIGGERED": "NO",
  "ASK_GIT_ROOT_MIGRATION_EXECUTED": "NO",
  "ASK_CODE_MODIFIED": "NO",
  "HERMES_CORE_MODIFIED": "NO",
  "PUSH_EXECUTED": "NO",
  "MERGE_EXECUTED": "NO",
  "PUBLISH_EXECUTED": "NO"
}
```

### 8 个指定用例

| 用例 | 输入 | 结果 | 关键输出 |
|---|---|---|---|
| explicit_ask_route | `对 ASK 项目检查状态` | exit=0 ok=true | project_id=ask; reason= |
| explicit_multiagent_route | `对 multiagent-orchestration-system 项目生成项目列表报告` | exit=0 ok=true | project_id=multiagent-orchestration-system; reason= |
| workspace_container_block | `在 /Users/hula/workspace 里执行项目任务` | exit=10 ok=true | project_id=blocked; reason=workspace_container_is_not_business_project |
| low_confidence_block | `继续做` | exit=10 ok=true | project_id=blocked; reason=low_confidence_requires_clarification |
| ask_high_risk_action_block | `对 ASK 执行 push 或自动 merge` | exit=10 ok=true | project_id=ask; reason=human_approval_required_or_ask_git_root_needs_migration |
| reporter_project_echo | `当前项目是什么？` | exit=0 ok=true | project_id=multiagent-orchestration-system; reason= |
| project_list | `当前一共有几个项目？` | exit=0 ok=true | project_id=ask; reason= |
| kanban_a2a_dry_run_metadata | `创建一个 dry-run work order，不派工。` | exit=0 ok=true | project_id=multiagent-orchestration-system; reason= |

P3 最终 JSON 证据：

```text
/tmp/p3-gateway-project-routing-validation-final.json
```

完整长输出如需查看，可参考本轮 Hermes 归档：

```text
/Users/hula/.hermes/tool_result_archive/20260629-031719__terminal__7c9ba0b3a70e.json
```

## 6. P2 回归验证

命令：

```bash
ruby scripts/validation/verify-task-guard-project-registry.rb
```

结果：

```text
P2_VALIDATION_EXIT=0
summary.total=21
summary.passed=21
summary.failed=0
forbidden_ask_status=[]
forbidden_multiagent_status=[]
```

P2 JSON 证据：

```text
/tmp/p3-p2-task-guard-project-registry-validation-final.json
```

## 7. Router smoke evidence

命令：

```bash
ruby scripts/gateway/project-router.rb --input '对 ASK 项目检查状态'
```

结果：

```text
exit=0
project_id=ask
board=ask
workspace_path=/Users/hula/workspace/ASK
git_root_status=needs_migration
worker_auto_dispatch_triggered=False
gateway_auto_dispatch_triggered=False
ASK_GIT_ROOT_STATUS=needs_migration
```

## 8. 禁止项验证

```text
ASK_CODE_MODIFIED=NO
HERMES_CORE_MODIFIED=NO
WORKER_AUTO_DISPATCH_TRIGGERED=NO
GATEWAY_AUTO_DISPATCH_TRIGGERED=NO
ASK_GIT_ROOT_MIGRATION_EXECUTED=NO
PUSH_EXECUTED=NO
MERGE_EXECUTED=NO
PUBLISH_EXECUTED=NO
```

状态检查：

```text
ASK/src ASK/tests ASK/packages ASK/.git status:
<empty>

Hermes core status:
<empty>
```

语法检查：

```text
Syntax OK
Syntax OK
Syntax OK
```

multiagent scoped status（仅用于说明本项目已有治理产物和本轮新增文件；未 commit）：

```text
M templates/a2a-work-order-protocol.md
?? config/projects.yaml
?? reports/ask-dirty-state-resolution-audit.md
?? reports/ask-gitignore-dirty-audit.md
?? reports/ask-gitignore-minimal-fix-report.md
?? reports/ask-gitignore-playwright-commit-prep-report.md
?? reports/ask-phase5-reverse-residue-cleanup-report.md
?? reports/hermes-project-boundary-and-management-audit.md
?? reports/p1-reporter-project-routing-report.md
?? reports/p2-blocked-forbidden-paths-diagnosis.md
?? reports/p2-task-guard-project-registry-report.md
?? reports/post-upgrade-project-management-plan.md
?? reports/project-overlay-registry-implementation-report.md
?? scripts/gateway/project-router.rb
?? scripts/validation/verify-gateway-project-routing.rb
?? scripts/validation/verify-task-guard-project-registry.rb
?? templates/gateway-project-routing-gate.md
?? templates/task-guard-project-registry-gate.md
```

## 9. 顾问复核结论

Gemini 与 Claude/GPT-style 顾问复核存在阶段定义差异：

- 第一轮：Gemini 认为模板/验证层足够；Claude 指出若 P3 要求实际 Gateway/Dispatcher runtime，则只做文档不够。
- 因此本轮补充了 `scripts/gateway/project-router.rb` dry-run Gateway router 包装入口，并将 P3 验证脚本改为真实调用该入口。
- 第二轮：Gemini 认可 P3 可收口；Claude 输出仍提醒“P3 是路由机制基础设施，真实 Hermes runtime 拦截/Feishu 命令接入仍应进入 P4”。

采用结论：P3 可作为 **dry-run Gateway 路由机制接入** 完成；不宣称已经修改 Hermes core 或已经接入真实运行时自动派发链路。

## 10. P4 判断

可以进入 P4，但 P4 的定义应明确为：

- Feishu 项目对话状态管理。
- `current_project` / `default_project` 持久化。
- `/project list`、`/project current`、`/project use` 的实际命令接入。
- 多项目状态总览。
- 将 `scripts/gateway/project-router.rb` 的 dry-run 路由能力接入真实 Gateway/Reporter 入口，同时继续保持默认 manual、不自动派发 coder。

P4 前置风险：当前 P3 没有修改 Hermes core，也没有实际写 Hermes 内部 DB；因此 P4 若要做真实命令/会话状态接入，需要单独授权修改对应入口，并继续禁止默认自动 worker 派发。
