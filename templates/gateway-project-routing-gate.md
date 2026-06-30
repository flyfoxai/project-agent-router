# Gateway Dispatcher Project Routing Gate

状态：P3 active gate template  
项目：Project Agent Router  
project_id：project-agent-router  
routing_source：/Users/hula/workspace/project-agent-router/config/projects.yaml  
适用范围：Gateway / Dispatcher 在任何任务进入 worker、Kanban、session 或 profile 前的项目路由、边界校验、阻断判断和 Reporter 回显。

## 1. 强制 registry 读取

Gateway / Dispatcher 接收任何任务后，进入以下任一路径前必须先读取 Project Overlay Registry：

```text
/Users/hula/workspace/project-agent-router/config/projects.yaml
```

强制点：

- 创建 worker 前。
- 创建 Kanban task 前。
- 绑定 session 前。
- 选择 profile 前。
- 生成 A2A `WORK_ORDER` 前。
- 生成拒绝、阻断、澄清或 Reporter 回显前。

如果 registry 缺失、YAML 不可解析、缺少 `ask` 或 `project-agent-router`，必须阻断：

```yaml
project_id: blocked
blocked: true
reason: registry_missing_or_invalid
requires_clarification: true
worker_auto_dispatch_triggered: false
gateway_auto_dispatch_triggered: false
```

不得用 shell cwd、记忆、上一轮摘要或默认 profile 替代 registry。

## 2. project_id 解析优先级

Gateway 接收任务前必须解析 `project_id`。解析来源优先级固定如下：

1. `explicit_project_id`：用户、任务 payload、A2A 消息或命令中显式给出 `project_id`。
2. `explicit_project_alias`：显式项目别名，例如 `ASK`、`ask`、`multiagent`、`multiagent-orchestration`。
3. `board_slug`：Kanban board slug 与 registry `default_board` 匹配。
4. `workspace_path`：输入 workspace_path 与 registry `business_root` / `project_root` / `task_guard_workspace` 唯一匹配。
5. `current_project`：显式会话状态中的 current_project；P3 只定义契约，不负责持久化，持久化留给 P4。
6. `default_project`：显式配置中的 default_project；P3 只定义契约，不负责持久化，持久化留给 P4。
7. `system/meta`：系统维护任务，且 project_id 明确为 `system` 或 `meta`。
8. `blocked_clarification`：仍无法唯一判断、命中多个项目、低置信度或只有模糊语义时阻断并澄清。

禁止规则：Gateway 不允许只靠 shell cwd 推断项目。如果只拿到 cwd，没有 project_id 或无法唯一映射，必须阻断并请求澄清。

模糊输入示例必须阻断：

```text
继续做
处理这个项目
派给 worker
让 agents 开始
把它改了
```

阻断输出必须包含候选项目列表，不得创建 task，不得派工。字段名固定为：

```yaml
candidate_projects:
  - ask
  - project-agent-router
```

## 3. registry 字段校验

解析到唯一项目后，Gateway 派工前必须校验 registry 中至少包含以下字段：

```yaml
project_id: required
board: registry.projects[project_id].default_board
workspace_path: registry.projects[project_id].task_guard_workspace or project_root
current_git_root: required
desired_git_root: required
git_root_status: required
dispatch_mode: registry.projects[project_id].dispatch.mode or registry.routing_policy.default_dispatch_mode
default_profile: required
```

缺任一字段必须阻断：

```yaml
project_id: blocked
blocked: true
reason: registry_required_field_missing
requires_clarification: true
```

## 4. Gateway task metadata 必填字段

任何 Gateway 生成的 task metadata 必须包含：

```yaml
project_id: "ask | project-agent-router | blocked"
project_display_name: "ASK | Project Agent Router | blocked"
board: "<registry default_board | blocked>"
workspace_path: "<registry task_guard_workspace/project_root | observed container>"
current_git_root: "<registry current_git_root | unknown>"
desired_git_root: "<registry desired_git_root | unknown>"
git_root_status: "needs_migration | independent | blocked | unknown"
dispatch_mode: "manual | blocked"
profile: "<registry default_profile | blocked>"
routing_source: "explicit_project_id | explicit_project_alias | board_slug | workspace_path | current_project | default_project | system_meta | blocked_clarification"
routing_confidence: "high | medium | low | blocked"
human_approval_required_for:
  - "push"
  - "merge"
  - "publish"
  - "git_root_migration"
  - "coder_concurrency_expansion"
```

## 5. Kanban / A2A Work Order 项目字段

Kanban task 与 A2A `WORK_ORDER` 必须带项目字段：

```yaml
project:
  project_id: "ask | project-agent-router | blocked"
  display_name: "ASK | Project Agent Router | blocked"
  board: "ask | project-agent-router | blocked"
  workspace_path: "<absolute path>"
  current_git_root: "<absolute path>"
  desired_git_root: "<absolute path>"
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
```

Dry-run work order 可以生成以上 metadata，但必须设置：

```yaml
dry_run: true
worker_auto_dispatch_triggered: false
gateway_auto_dispatch_triggered: false
real_worker_task_created: false
```

## 6. ASK 特殊规则

ASK 当前 registry 事实：

```yaml
project_id: ask
project_root: /Users/hula/workspace/ASK
current_git_root: /Users/hula/workspace
desired_git_root: /Users/hula/workspace/ASK
git_root_status: needs_migration
```

Gateway 对 ASK 必须：

- 允许只读诊断类任务。
- 允许人工批准的低风险配置类任务。
- 禁止自动 commit / push / merge / publish。
- 禁止 Git root migration 自动执行。
- 禁止在没有人工批准时扩大 coder 并发。
- 每次报告都提示：`ASK_GIT_ROOT_STATUS=needs_migration`。

ASK 高风险动作必须阻断：

```yaml
project_id: ask
blocked: true
reason: human_approval_required_or_ask_git_root_needs_migration
worker_auto_dispatch_triggered: false
gateway_auto_dispatch_triggered: false
```

高风险动作包括但不限于：`push`、`merge`、`publish`、自动 commit、git root migration、扩大 coder 并发、创建可写 coder worker。

## 7. project-agent-router 规则

project-agent-router 当前 registry 事实：

```yaml
project_id: project-agent-router
git_root_status: independent
```

允许在其独立 Git root 内做项目治理文件修改、模板修改、报告生成和验证脚本。

仍禁止：

- push
- publish
- merge
- git reset / checkout / rm / mv
- Gateway 自动派发 coder
- 扩大 coder 并发

除非人工另行明确批准。

## 8. 父级 workspace 容器阻断

`/Users/hula/workspace` 不得作为普通业务项目。

机器可检索规则句：/Users/hula/workspace 不得作为普通业务项目。

如果 Gateway 解析到：

```yaml
workspace_path: /Users/hula/workspace
```

但 project_id 不是 `system` 或 `meta`，必须阻断：

```yaml
project_id: blocked
blocked: true
reason: workspace_container_is_not_business_project
workspace_path: /Users/hula/workspace
worker_auto_dispatch_triggered: false
gateway_auto_dispatch_triggered: false
```

## 9. Reporter 项目头回显

任何 Gateway 创建、拒绝、阻断、澄清的结果，都必须带项目头：

```text
项目：<display_name | blocked>
project_id：<project_id | blocked>
board：<board | blocked>
workspace_path：<absolute path | unknown>
git_root：<current_git_root | observed git root | unknown>
git_root_status：<needs_migration | independent | blocked | unknown>
dispatch_mode：<manual | blocked>
routing_source：<source>
routing_confidence：<high | medium | low | blocked>
```

Reporter 不得省略 ASK 的：

```text
ASK_GIT_ROOT_STATUS=needs_migration
```

## 10. 禁止自动派发

P3 只接入 Gateway / Dispatcher 项目路由契约、验证脚本和报告。P3 不授权：

```yaml
worker_auto_dispatch_triggered: false
gateway_auto_dispatch_triggered: false
real_worker_task_created: false
coder_concurrency_expansion_allowed: false
```

任何 dry-run 生成的 Kanban / A2A metadata 都不得被真实 worker 拾取。

## 11. 完成前检查清单

- [ ] 已回读并解析 `config/projects.yaml`。
- [ ] registry 包含 `ask` 与 `project-agent-router`。
- [ ] project_id 解析优先级已固化。
- [ ] 只靠 cwd 无法唯一映射时阻断。
- [ ] Gateway task metadata 包含项目字段。
- [ ] Kanban / A2A Work Order 包含 `project` 与 `routing` 字段。
- [ ] `/Users/hula/workspace` 父级容器误用会阻断。
- [ ] 低置信度模糊任务会阻断并输出候选项目。
- [ ] ASK 高风险动作会阻断。
- [ ] Reporter 项目头回显已固化。
- [ ] Dry-run work order 不派发 worker。
- [ ] P2 验证仍通过。
- [ ] P3 验证脚本通过。
- [ ] 未修改 ASK 业务代码、Hermes core，未 push/merge/publish。
