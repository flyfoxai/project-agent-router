# Channel-Agnostic Project Conversation Adapter

状态：P4 dry-run contract template  
项目：Project Agent Router  
project_id：project-agent-router  
适用范围：对话层项目状态、项目命令解析、通道 adapter 映射、Reporter 项目回显。

## 1. 目标

P4 将 P0-P3 的 Project Overlay Registry、Reporter 项目头、task_guard、Gateway dry-run router 接入“对话层”。

设计必须通道无关：

- 不修改 Hermes core。
- 不直接写 Hermes 内部 DB。
- 不把逻辑写死到 Feishu。
- 项目对话状态和 channel 解耦。
- 命令解析和 channel 解耦。
- Feishu 只是第一个 dry-run adapter。
- 未来 Slack、微信、Discord 只新增 adapter，不重写项目路由核心。
- 所有项目数据仍从 `config/projects.yaml` 读取。
- 项目路由复用 P3 `scripts/gateway/project-router.rb`。
- 默认 manual，禁止自动 coder 派发。

## 2. 分层架构

```text
conversation-core
- parse project commands
- maintain current_project / default_project
- call scripts/gateway/project-router.rb dry-run
- generate channel-neutral response

channel-adapter
- feishu adapter now
- slack adapter later
- wechat adapter later
- discord adapter later

state-store
- channel + conversation_id + user_id scoped state
- do not write Hermes internal DB
- local file under project-agent-router for now
```

## 3. ConversationMessage 通用输入格式

所有通道必须先映射成同一个 channel-neutral message：

```yaml
channel: feishu
conversation_id: feishu-chat-xxx
user_id: user-xxx
message_id: msg-xxx
text: 当前项目是什么？
timestamp: "2026-06-29T12:00:00+08:00"
metadata:
  raw_platform: feishu
```

Slack / 微信 / Discord 后续只新增 adapter：

```yaml
channel: slack
conversation_id: slack-channel-xxx
user_id: slack-user-xxx
message_id: slack-msg-xxx
text: /project current
timestamp: "2026-06-29T12:00:00+08:00"
metadata:
  raw_platform: slack
```

## 4. ConversationResponse 通用输出格式

```yaml
mode: "project_command | project_task | ask | system_meta | blocked"
project_id: "ask | project-agent-router | blocked | null"
project_display_name: "ASK | Project Agent Router | blocked | null"
routing_source: "explicit_project | current_project | default_project | ask_mode | system_meta | blocked_clarification"
routing_confidence: "high | medium | low | blocked"
requires_clarification: false
response_text: "<channel-neutral text>"
reporter_header: |
  项目：<label>
  project_id：<id>
  board：<board>
  workspace_path：<path>
  git_root：<git_root>
  git_root_status：<status>
  dispatch_mode：manual
project_label: "<display label>"
board: "<board | null>"
workspace_path: "<absolute path | null>"
git_root: "<current_git_root | null>"
git_root_status: "needs_migration | independent | null | blocked"
dispatch_mode: "manual | blocked"
actions:
  update_current_project: "ask | project-agent-router | null | unchanged"
  update_default_project: "ask | project-agent-router | null | unchanged"
dry_run_work_order: null
worker_auto_dispatch_triggered: false
gateway_auto_dispatch_triggered: false
```

## 5. 状态存储 schema

状态文件必须位于 multiagent 项目内，例如：

```text
/Users/hula/workspace/project-agent-router/state/conversations/sample-state.json
```

schema：

```json
{
  "version": 1,
  "conversations": {
    "<channel>:<conversation_id>:<user_id>": {
      "current_project": "ask",
      "default_project": "project-agent-router",
      "updated_at": "2026-06-29T12:00:00+08:00",
      "last_routing_source": "project_use",
      "last_message_id": "msg-xxx"
    }
  }
}
```

硬规则：

- state key 必须包含 `channel`。
- `conversation_id` 和 `user_id` 必须参与 key。
- 禁止使用全局单一 `current_project` 污染所有聊天入口。
- P4 只允许写 multiagent 项目内 dry-run/sample state。
- 禁止写 Hermes 内部 DB。

## 6. 必须支持的命令

```text
/project list
/project current
/project use ask
/project use project-agent-router
/project default ask
/project clear
/system status
/orchestration status
/ask 只做通用分析
```

自然语言等价表达：

```text
当前一共有几个项目？
现在有哪些项目？
当前项目是什么？
我下面说的话对哪个项目有效？
切到 ASK
切到 project-agent-router
接下来都按 ASK 项目处理
取消当前项目
只做通用分析，不进入项目
```

## 7. 路由语义

优先级：

```text
显式项目 > 当前项目 > 默认项目 > 通用 ASK/分析问题 > system/meta > 澄清
```

规则：

1. `/project use <project>`：校验项目存在，更新当前 conversation 的 `current_project`，不创建 worker，不写 Kanban task。
2. `/project current`：返回当前项目、默认项目、后续未指定项目时的作用对象。
3. `/project list`：从 `projects.yaml` 列出所有项目，标记 current/default。
4. `/project default <project>`：设置 `default_project`，不覆盖已有 `current_project`。
5. `/project clear`：清空 `current_project`，保留 `default_project`。
6. `/ask` 或“只做通用分析”：`mode=ask`，不进入项目。
7. `/system status` 或 `/orchestration status`：`mode=system_meta`，不进入普通业务项目。
8. 低置信度：`mode=blocked`，`project_id=blocked`，请求澄清，不创建任务。

## 8. Feishu dry-run adapter

Feishu adapter 只负责把 Feishu DM / topic / message 映射成 `ConversationMessage`：

```yaml
channel: feishu
conversation_id: "<Feishu chat id or topic id>"
user_id: "<Feishu sender id>"
message_id: "<Feishu message id>"
text: "<message text>"
timestamp: "<message timestamp>"
metadata:
  raw_platform: feishu
```

Feishu adapter 不拥有项目路由逻辑，不直接改 state，不创建 worker，不写 Kanban。它只调用 conversation-core。

未来 adapter：

```text
Slack adapter  -> ConversationMessage -> conversation-core -> ConversationResponse -> Slack formatting
WeChat adapter -> ConversationMessage -> conversation-core -> ConversationResponse -> WeChat formatting
Discord adapter -> ConversationMessage -> conversation-core -> ConversationResponse -> Discord formatting
```

## 9. 禁止项

P4 不授权：

```yaml
worker_auto_dispatch_triggered: false
gateway_auto_dispatch_triggered: false
real_worker_task_created: false
hermes_core_modified: false
hermes_internal_db_modified: false
production_webhook_connected: false
```

禁止：

- 修改 ASK 业务代码。
- 迁移 ASK `.git`。
- 修改 ASK Git root。
- 修改 Hermes core。
- 直接写 Hermes 内部 DB。
- 接入真实生产 Feishu webhook。
- 接入真实 Slack、微信、Discord webhook。
- 创建真实 worker 编码任务。
- Gateway 自动派发 coder。
- 扩大 coder 并发。
- push / merge / publish / auto commit。

## 10. P5 前置判断

P4 完成后，P5 可以进入真实 Feishu 命令入口小流量接入，但必须继续：

- 保持 manual dispatch。
- 不自动派发 coder。
- 不写 Hermes 内部 DB，除非单独授权并完成兼容性设计。
- 先以 Feishu adapter 调用 channel-neutral core，不把逻辑写死到 Feishu。
