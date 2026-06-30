# Task Guard Project Overlay Registry Gate

状态：active gate template  
项目：Project Agent Router  
project_id：project-agent-router  
routing_source：/Users/hula/workspace/project-agent-router/config/projects.yaml  
适用范围：task_guard / project guard / dispatcher / reporter 在执行任务前的项目边界检查。

## 1. 目标

本 gate 让 task_guard 在执行任何普通任务、记录 evidence、生成阻断消息或汇报前，先读取 Project Overlay Registry：

```text
/Users/hula/workspace/project-agent-router/config/projects.yaml
```

并使用 registry 做项目边界检查，防止 ASK、project-agent-router、父级 `/Users/hula/workspace` 被混淆。

本文件是 project-agent-router 仓库内的项目治理模板，不是 Hermes core 修改，不直接写 Hermes 内部 DB。

## 2. 启动前强制读取

- task_guard 启动或接收任务前必须读取 `config/projects.yaml`。
- registry 缺失、YAML 解析失败、缺少 `projects.ask` 或 `projects.project-agent-router` 时，不执行任务。
- 读取失败时必须输出阻断项目头，并设置：
  - `project_id=blocked`
  - `dispatch_mode=blocked`
  - `routing_confidence=blocked`

阻断消息必须请求人工澄清，不得使用当前目录、记忆或上一轮摘要替代 registry。

## 3. 项目三元组

所有 task_guard evidence、阻断消息、报告和执行前检查必须使用三元组识别项目：

```yaml
project_id: "ask | project-agent-router | blocked"
workspace_path: "<registry task_guard_workspace or project_root>"
git_root: "<registry current_git_root plus live verification>"
```

普通任务必须能解析出唯一 `project_id`。解析顺序：

1. 显式 `project_id`。
2. task_guard evidence 中的 `project_id/workspace_path/git_root`。
3. registry 中的 `workspace_path`、`business_root`、`project_root` 匹配。
4. board / Kanban / 当前项目上下文匹配。
5. 当前 Git top-level 与 registry `current_git_root` 匹配。
6. 仍无法唯一解析时阻断执行并请求澄清。

## 4. workspace_path 检查

`workspace_path` 必须匹配 registry：

| project_id | workspace_path |
|---|---|
| ask | `/Users/hula/workspace/ASK` |
| project-agent-router | `/Users/hula/workspace/project-agent-router` |

如果检测到任务 workspace 是 `/Users/hula/workspace`，但 `project_id` 不是 `system` 或 `meta`，必须阻断并提示：

```text
/Users/hula/workspace 是父级容器，不应作为普通业务项目执行。
```

该场景必须设置：

```yaml
project_id: blocked
workspace_path: /Users/hula/workspace
dispatch_mode: blocked
```

## 5. git_root 检查

`git_root` 必须匹配 registry，并以 live `git rev-parse --show-toplevel` 作为完成前验证证据。

ASK：

```yaml
project_id: ask
workspace_path: /Users/hula/workspace/ASK
current_git_root: /Users/hula/workspace
desired_git_root: /Users/hula/workspace/ASK
git_root_status: needs_migration
```

project-agent-router：

```yaml
project_id: project-agent-router
workspace_path: /Users/hula/workspace/project-agent-router
current_git_root: /Users/hula/workspace/project-agent-router
desired_git_root: /Users/hula/workspace/project-agent-router
git_root_status: independent
```

如果 live Git root 与 registry 不一致，task_guard 必须阻断执行并请求澄清或人工确认。

## 6. ASK 高风险 Git 操作 gate

对 ASK 的以下高风险 Git 操作必须阻断或要求人工单独确认：

- `git commit`
- `git push`
- `git merge`
- `git rebase`
- `git reset`
- destructive `git checkout`
- branch rewrite
- git root migration
- `.git` / `.gitignore` 相关修改

ASK 允许低风险只读检查：

- `git status`
- `git diff`
- `git log`
- `git rev-parse`
- 文件读取

但所有 ASK 报告必须提示：

```text
ASK_GIT_ROOT_STATUS=needs_migration
```

## 7. project-agent-router gate

对 project-agent-router：

- 允许在其独立 Git root 内进行低风险项目管理文件修改。
- 允许范围包括本项目内的 `templates/`、`reports/`、`scripts/validation/`、`config/projects.yaml` 的只读验证或经任务明确授权的 registry 文档治理。
- 仍禁止 `push` / `publish` / `merge`，除非人工单独批准。
- 仍禁止 `git reset` / destructive `checkout` / `git rm` / `git mv`，除非人工单独批准。

## 8. 项目头要求

task_guard 报告和阻断消息必须包含项目头：

```yaml
项目: "<display_name | blocked>"
project_id: "<project_id | blocked>"
workspace_path: "<absolute path | unknown>"
git_root: "<absolute path | unknown>"
git_root_status: "independent | needs_migration | blocked | unknown"
dispatch_mode: "manual | blocked | read_only | approved_write_scoped"
```

## 9. 阻断与澄清

以下情况必须不执行任务，设置 `project_id=blocked`，并请求人工澄清：

- 缺 registry。
- registry YAML 解析失败。
- `project_id` 缺失且无法唯一解析。
- `workspace_path` 与 registry 不匹配。
- live `git_root` 与 registry `current_git_root` 不匹配。
- routing confidence 为 low / blocked。
- 命中多个项目。
- `/Users/hula/workspace` 被当作普通业务项目 workspace。
- ASK 高风险 Git 操作没有人工单独确认。

## 10. 阻断消息模板

```yaml
项目: blocked
project_id: blocked
workspace_path: "<observed workspace_path | unknown>"
git_root: "<observed git_root | unknown>"
git_root_status: blocked
dispatch_mode: blocked
reason: "registry_missing | registry_parse_failed | ambiguous_project | workspace_mismatch | git_root_mismatch | workspace_container_blocked | ask_high_risk_git_needs_human_approval | low_confidence"
clarification_request: "请确认目标 project_id、workspace_path、允许的操作范围，以及是否批准高风险 Git 操作。"
```

## 11. 完成前检查清单

- [ ] 已读取 `/Users/hula/workspace/project-agent-router/config/projects.yaml`。
- [ ] registry YAML 可解析。
- [ ] projects 包含 `ask` 和 `project-agent-router`。
- [ ] 使用 `project_id + workspace_path + git_root` 三元组识别项目。
- [ ] ASK `git_root_status=needs_migration` 已在报告中提示。
- [ ] multiagent `git_root_status=independent | ok` 已验证。
- [ ] `/Users/hula/workspace` 父级容器误用会阻断。
- [ ] ASK 高风险 Git 操作会阻断或要求人工确认。
- [ ] 报告和阻断消息包含项目头。
- [ ] 缺 registry / 解析失败 / 项目不匹配 / 低置信度路由时不执行任务并请求澄清。
