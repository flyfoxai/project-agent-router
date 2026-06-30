# P4 Channel-Agnostic Project Conversation Adapter Report

项目：Multi-Agent Orchestration System  
project_id：multiagent-orchestration-system  
生成时间：2026-06-29T13:56:23+08:00  
报告路径：`/Users/hula/workspace/multiagent-orchestration-system/reports/p4-channel-agnostic-conversation-adapter-report.md`

## 1. 结论

P4 可以按 **通道无关核心 + Feishu dry-run adapter** 收口。

本轮完成的是对话层 dry-run 接入：

- `conversation-core`：命令解析、`current_project` / `default_project` 状态维护、调用 P3 Gateway dry-run router、输出通道无关响应。
- `state-store`：项目内 dry-run JSON state，key 为 `channel:conversation_id:user_id`，避免全局 current_project 污染。
- `channel-adapter contract`：Feishu 只是第一个 adapter；未来 Slack、微信、Discord 只需把各自消息映射成 `ConversationMessage`。

未做且禁止项保持未触发：

- 未修改 Hermes core。
- 未直接写 Hermes 内部 DB。
- 未接入真实生产 Feishu webhook。
- 未接入 Slack、微信、Discord webhook。
- 未创建真实 worker。
- 未自动派发 coder。
- 未扩大 coder 并发。
- 未修改 ASK 业务代码或 ASK Git root。
- 未 push / merge / publish / auto commit。

## 2. 必填字段

```text
P4_CHANNEL_AGNOSTIC_CORE_READY=YES
P4_FEISHU_ADAPTER_DRY_RUN_READY=YES
P4_SLACK_WECHAT_DISCORD_FUTURE_ADAPTER_READY=YES
P4_CONVERSATION_MESSAGE_SCHEMA_READY=YES
P4_CONVERSATION_RESPONSE_SCHEMA_READY=YES
P4_STATE_STORE_SCHEMA_READY=YES
P4_CURRENT_PROJECT_READY=YES
P4_DEFAULT_PROJECT_READY=YES
P4_PROJECT_LIST_READY=YES
P4_PROJECT_USE_READY=YES
P4_PROJECT_CLEAR_READY=YES
P4_SYSTEM_META_READY=YES
P4_LOW_CONFIDENCE_BLOCK_READY=YES
P4_CHANNEL_ISOLATION_READY=YES
P4_VALIDATION_PASSED=YES
P3_REGRESSION_PASSED=YES
P2_REGRESSION_PASSED=YES
WORKER_AUTO_DISPATCH_TRIGGERED=NO
GATEWAY_AUTO_DISPATCH_TRIGGERED=NO
ASK_GIT_ROOT_MIGRATION_EXECUTED=NO
ASK_CODE_MODIFIED=NO
HERMES_CORE_MODIFIED=NO
HERMES_INTERNAL_DB_MODIFIED=NO
PUSH_EXECUTED=NO
MERGE_EXECUTED=NO
PUBLISH_EXECUTED=NO
```

## 3. 本轮新增/修改文件

```text
templates/channel-agnostic-conversation-adapter.md
scripts/conversation/project-conversation-router.rb
scripts/validation/verify-channel-agnostic-conversation-adapter.rb
state/conversations/sample-state.json
state/conversations/p4-validation-state.json
reports/p4-channel-agnostic-conversation-adapter-report.md
```

其中 `state/conversations/p4-validation-state.json` 是 P4 验证用项目内 dry-run 状态文件，不是生产会话状态。

## 4. 架构说明

```text
conversation-core
- parse project commands
- maintain current_project / default_project
- call scripts/gateway/project-router.rb dry-run
- generate channel-neutral response

channel-adapter
- feishu adapter now as dry-run contract
- slack adapter later
- wechat adapter later
- discord adapter later

state-store
- channel + conversation_id + user_id scoped state
- no Hermes internal DB write
- local file under multiagent-orchestration-system/state/conversations for P4
```

关键边界：

- `scripts/conversation/project-conversation-router.rb` 输入是通用 `ConversationMessage` JSON。
- 输出是通用 `ConversationResponse` JSON。
- core 不读取 Feishu webhook payload，不调用 Feishu API，不包含 Feishu-only 状态 key。
- Feishu adapter 未来只负责平台消息与 `ConversationMessage`/`ConversationResponse` 的双向转换。

## 5. ConversationMessage / ConversationResponse / State Schema

已在 `templates/channel-agnostic-conversation-adapter.md` 固化：

- `ConversationMessage` 必含：`channel`、`conversation_id`、`user_id`、`message_id`、`text`、`timestamp`、`metadata.raw_platform`。
- `ConversationResponse` 必含：`mode`、`project_id`、`project_display_name`、`routing_source`、`routing_confidence`、`requires_clarification`、`response_text`、`reporter_header`、`project_label`、`board`、`workspace_path`、`git_root`、`git_root_status`、`dispatch_mode`、`actions`、`dry_run_work_order`、`worker_auto_dispatch_triggered=false`、`gateway_auto_dispatch_triggered=false`。
- state key：`<channel>:<conversation_id>:<user_id>`。

## 6. P4 验证用例结果

```text
P4_EXIT=0
P4_SUMMARY total=30 passed=30 failed=0
```

- project_list_natural_language: PASS; exit=0; mode=project_command; project_id=None; current=None; default=None
- current_project_empty: PASS; exit=0; mode=project_command; project_id=None; current=None; default=None
- use_ask_natural_language: PASS; exit=0; mode=project_command; project_id=ask; current=ask; default=None
- project_use_multiagent_command: PASS; exit=0; mode=project_command; project_id=multiagent-orchestration-system; current=multiagent-orchestration-system; default=None
- routing_scope_explanation: PASS; exit=0; mode=project_command; project_id=multiagent-orchestration-system; current=multiagent-orchestration-system; default=None
- project_clear: PASS; exit=0; mode=project_command; project_id=None; current=None; default=None
- project_default_ask: PASS; exit=0; mode=project_command; project_id=ask; current=None; default=ask
- ask_mode_no_project: PASS; exit=0; mode=ask; project_id=None; current=None; default=ask
- orchestration_status_system_meta: PASS; exit=0; mode=system_meta; project_id=None; current=None; default=ask
- low_confidence_block: PASS; exit=10; mode=blocked; project_id=blocked; current=None; default=None
- channel_isolation: PASS; exit=[0, 0, 0, 0]; mode=None; project_id=None; current=None; default=None

## 7. P3 / P2 回归结果

```text
P3_EXIT=0
P3_SUMMARY total=22 passed=22 failed=0

P2_EXIT=0
P2_SUMMARY total=21 passed=21 failed=0
```

## 8. 禁止项验证

最终只读检查摘要：

```text
registry=YAML_OK projects=ask,multiagent-orchestration-system
ask_business_status=
hermes_core_status=
hermes_internal_db_newer=
state_files=state/conversations/p4-validation-state.json state/conversations/sample-state.json
```

解释：

- ASK 业务代码 forbidden status 为空，表示本轮未修改 `ASK/src`、`ASK/tests`、`ASK/packages`、`ASK/.git`。
- Hermes core/internal DB 检查未发现本轮脚本写入 Hermes 内部 DB 文件。
- 状态文件只位于 multiagent 项目内 `state/conversations/`。
- 所有 worker/Gateway 自动派发标志均为 `NO`。

## 9. 顾问复核共识

Gemini CLI 与 Claude CLI 只读顾问复核均支持 P4 收口。

共同结论：

- P4 可按“通道无关核心 + Feishu dry-run adapter”收口。
- 未发现核心逻辑写死到 Feishu 的证据。
- 未发现 Hermes core、Hermes internal DB、worker 自动派发风险。
- P5 可以进入“真实 Feishu 命令入口小流量接入”，但必须继续保持 manual dispatch，不自动派发 coder。

共同风险：

- P5 真实流量前需要处理本地 JSON state 的并发/锁/竞态问题。
- 需要明确用户权限、项目 ACL、输入校验、审计日志、rate limit、错误降级和回滚策略。
- 自然语言项目命令需要继续保守处理，低置信度应澄清而不是自动进入项目。

## 10. P5 判断

可以进入 P5。

P5 建议范围：真实 Feishu 命令入口小流量接入，但仍保持：

- manual dispatch。
- 不自动派发 coder。
- Feishu adapter 只做 webhook/消息格式转换与响应格式转换。
- 真实入口必须调用 P4 `ConversationMessage -> conversation-core -> ConversationResponse`，禁止把项目路由逻辑写入 Feishu adapter。
- 不写 Hermes 内部 DB，除非另开设计/授权。
- 加入状态锁或单线程队列，避免同一 conversation 并发写 JSON state。
- 加入用户白名单、权限校验、审计日志、输入校验与快速禁用开关。
