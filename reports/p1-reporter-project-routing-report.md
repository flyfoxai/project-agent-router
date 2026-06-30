# P1 Reporter 项目路由模板接入报告

项目：Multi-Agent Orchestration System  
project_id：multiagent-orchestration-system  
业务根：/Users/hula/workspace/multiagent-orchestration-system  
项目根：/Users/hula/workspace/multiagent-orchestration-system  
当前 Git 根：/Users/hula/workspace/multiagent-orchestration-system  
目标 Git 根：/Users/hula/workspace/multiagent-orchestration-system  
Git 状态：independent  
task_guard workspace：/Users/hula/workspace/multiagent-orchestration-system  
目标仓库：/Users/hula/workspace/multiagent-orchestration-system  
验证状态：focused verification passed

## 1. 结论

P1 已完成低风险文档接入：`templates/a2a-work-order-protocol.md` 的 `HUMAN_REPORT` 模板和 gate 现在明确要求 Reporter 在生成人工汇报前读取 `config/projects.yaml`，输出项目头，并处理项目查询、项目切换和歧义阻断。

本次未修改代码、包配置、ASK 目录、Git 配置，也未执行 commit / push / merge / reset / checkout 等 Git 破坏性操作。

## 2. 修改范围

### 已修改

- `templates/a2a-work-order-protocol.md`
  - 在 `HUMAN_REPORT.project` 块中补齐项目身份字段：`project_id`、`display_name`、`business_root`、`project_root`、`current_git_root`、`desired_git_root`、`git_root_status`、`task_guard_workspace`、`target_repository`、`routing_source`、`routing_basis`、`routing_confidence`、`header_required`。
  - 在 `HUMAN_REPORT gate` 中新增强制约束：
    - Reporter 生成任何 `HUMAN_REPORT` 前必须读取 `config/projects.yaml`。
    - 项目查询必须按 `routing_policy.conflict_resolution_order` 执行。
    - 命中多个项目、缺少 registry 条目或置信度低时，必须阻断为 `project.project_id=blocked` 并请求澄清。
    - 项目切换必须来自新的 `WORK_ORDER`、`HANDOFF` 或人工指令，并重新读取 registry、重新验证项目根/Git 根/目标仓库。
    - 面向老板的结论必须先说项目名和结论。

### 已新增

- `reports/p1-reporter-project-routing-report.md`

### 未修改 / 禁止项

- 未修改 `config/projects.yaml`。
- 未修改 `.gitignore`、`package.json`、`pnpm-lock.yaml`。
- 未修改 ASK 项目目录。
- 未修改源代码目录。
- 未执行自动 Gateway 派工或 coder 并发扩容。

## 3. 验证记录

执行位置：`/Users/hula/workspace/multiagent-orchestration-system`

### 3.1 Registry YAML 读取

命令要点：`python3` 读取 `config/projects.yaml` 并检查项目列表与报告项目头策略。

结果：

```text
YAML_OK=YES
PROJECTS=ask,multiagent-orchestration-system
MISSING_REQUIRED=NONE
REPORT_HEADER_REQUIRED=TRUE
```

### 3.2 Reporter 模板关键约束检查

检查字符串：

- `project:`
- `routing_source: "config/projects.yaml"`
- `Reporter 必须先读取 `config/projects.yaml``
- `routing_policy.conflict_resolution_order`
- `项目切换必须由新的 `WORK_ORDER``
- `project.project_id=blocked`
- `summary.conclusion_first`

结果：

```text
TEMPLATE_REQUIRED_STRINGS_OK=YES
TEMPLATE_MISSING=NONE
```

### 3.3 Git 根验证

结果：

```text
GIT_ROOT=/Users/hula/workspace/multiagent-orchestration-system
```

### 3.4 变更范围验证

Scoped status：

```text
 M templates/a2a-work-order-protocol.md
?? config/projects.yaml
?? reports/hermes-project-boundary-and-management-audit.md
?? reports/post-upgrade-project-management-plan.md
?? reports/project-overlay-registry-implementation-report.md
```

说明：`config/projects.yaml` 和既有 `reports/*.md` 是前序任务产生的未跟踪文件；本 P1 只修改 `templates/a2a-work-order-protocol.md`，并新增本报告。

禁止项检查：

```text
FORBIDDEN_STATUS_START
FORBIDDEN_STATUS_END
```

Diff name-status：

```text
M	templates/a2a-work-order-protocol.md
```

## 4. 当前状态

- P1 实现：完成。
- P1 focused verification：完成。
- P1 报告：已写入并已回读核验。
- 需要老板决策：无。
- 风险：当前仓库仍有前序未跟踪 registry/report 文件；这不是 P1 新引入风险，但后续提交或归档时需要统一处理。

## 5. 完成标准对照

- [x] Reporter 模板强制读取 `config/projects.yaml`。
- [x] `HUMAN_REPORT` 包含项目头字段。
- [x] 项目查询使用 registry 冲突消解顺序。
- [x] 项目切换要求重新读取 registry 并重新验证路径。
- [x] 歧义/低置信度场景阻断并请求澄清。
- [x] 最小验证通过。
- [x] 禁止项未触碰。
