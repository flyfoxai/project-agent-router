# P5a Feishu Command Ingress Report

项目：Multi-Agent Orchestration System  
project_id：multiagent-orchestration-system  
生成时间：2026-06-29T14:23:50+08:00  
报告路径：`/Users/hula/workspace/multiagent-orchestration-system/reports/p5a-feishu-command-ingress-report.md`

## 1. 结论

P5a 可以按 **Feishu adapter runtime entry + P4 conversation-core reused + dry-run/manual dispatch** 收口。

本轮完成的是 Feishu 小流量项目管理命令入口：

- Feishu adapter 接收 Feishu message event JSON。
- Feishu adapter 转换为 P4 `ConversationMessage`。
- Feishu adapter 调用 `scripts/conversation/project-conversation-router.rb`。
- Feishu adapter 将 P4 `ConversationResponse` 转成 Feishu text reply payload。
- 项目路由、`current_project` / `default_project`、低置信度阻断等逻辑继续由 P4 conversation-core 负责。
- 默认 dry-run/manual dispatch，不创建真实 worker，不自动派发 coder。

## 2. 本轮新增/修改文件

```text
config/feishu-command-adapter.yaml
scripts/adapters/feishu/feishu-command-adapter.rb
scripts/validation/verify-p5a-feishu-command-ingress.rb
logs/feishu-adapter/p5a-validation-audit.jsonl
state/conversations/p5a-validation-state.json
state/conversations/p5a-rate-limit-state.json
state/conversations/p5a-input-*.json
reports/p5a-feishu-command-ingress-report.md
```

说明：`logs/feishu-adapter/p5a-validation-audit.jsonl`、`state/conversations/p5a-*` 是 P5a 验证生成的项目内 dry-run 证据，不是 Hermes internal DB，也不是生产 Feishu webhook 状态。

## 3. 必填字段

```text
P5A_FEISHU_ADAPTER_READY=YES
P5A_CONVERSATION_CORE_REUSED=YES
P5A_PROJECT_COMMANDS_READY=YES
P5A_WHITELIST_READY=YES
P5A_RATE_LIMIT_READY=YES
P5A_AUDIT_LOG_READY=YES
P5A_DISABLE_SWITCH_READY=YES
P5A_STATE_LOCK_READY=YES
P5A_WORKER_AUTO_DISPATCH_TRIGGERED=NO
P5A_GATEWAY_AUTO_DISPATCH_TRIGGERED=NO
P4_REGRESSION_PASSED=YES
P3_REGRESSION_PASSED=YES
P2_REGRESSION_PASSED=YES
ASK_CODE_MODIFIED=NO
HERMES_CORE_MODIFIED=NO
HERMES_INTERNAL_DB_MODIFIED=NO
PUSH_EXECUTED=NO
MERGE_EXECUTED=NO
PUBLISH_EXECUTED=NO
```

## 4. Adapter 边界

`config/feishu-command-adapter.yaml` 约束：

```text
manual_dispatch_only=true
worker_auto_dispatch_allowed=false
gateway_auto_dispatch_allowed=false
allowed_commands=/project list,/project current,/project use <project_id>,/project default <project_id>,/project clear,/system status,/orchestration status
rate_limit.max_commands=3
rate_limit.window_seconds=60
```

`feishu-command-adapter.rb` 只负责 channel adapter：

```text
Feishu event JSON
  -> ConversationMessage(channel=feishu, conversation_id, user_id, message_id, text, timestamp, metadata)
  -> P4 conversation-core
  -> ConversationResponse
  -> Feishu reply_payload(receive_id_type=chat_id,msg_type=text,content={text})
```

项目管理逻辑不在 Feishu adapter 内实现；项目路由继续复用 P4 conversation-core。

## 5. 安全控制

P5a 已实现并验证：

- 用户白名单：非白名单返回 `user_not_whitelisted`。
- 输入校验：只允许项目管理命令，拒绝 shell 特征字符与非授权命令。
- Rate limit：同一 `conversation_id:user_id` 在窗口内超过阈值返回 `rate_limited`。
- Audit log：JSONL 记录 `channel`、`conversation_id`、`user_id`、`project_id`、`action`、`result`、`timestamp`。
- State lock：使用 `File.flock(File::LOCK_EX)` 包住 adapter 关键区。
- Disable switch：`--disabled` 或 config `feature_enabled=false` 可快速禁用入口。
- Dispatch safety：所有 adapter/core 响应均保持 `worker_auto_dispatch_triggered=false`、`gateway_auto_dispatch_triggered=false`。

## 6. P5a 验证结果

```text
P5A_EXIT=0
P5A_SUMMARY total=25 passed=25 failed=0
AUDIT_LOG=/Users/hula/workspace/multiagent-orchestration-system/logs/feishu-adapter/p5a-validation-audit.jsonl
AUDIT_RECORD_COUNT=10
```

- feishu_to_conversation_message_core_reply: PASS; exit=0; result=ok; reason=ok
- project_use_ask_real_entry: PASS; exit=0; result=ok; reason=ok
- whitelist_blocks_user: PASS; exit=12; result=blocked; reason=user_not_whitelisted
- input_validation_blocks_unsafe_command: PASS; exit=13; result=blocked; reason=input_validation_failed
- rate_limit_blocks_after_threshold: PASS; exit=[0, 0, 0, 14, 14]; result=rate_limited; reason=rate_limited
- disable_switch_blocks: PASS; exit=11; result=disabled; reason=adapter_disabled
- audit_log_required_fields: PASS; exit=0; result=None; reason=None
- state_lock_ready: PASS; exit=0; result=None; reason=None

## 7. 回归验证

```text
P4_EXIT=0
P4_SUMMARY total=30 passed=30 failed=0

P3_EXIT=0
P3_SUMMARY total=22 passed=22 failed=0

P2_EXIT=0
P2_SUMMARY total=21 passed=21 failed=0
```

## 8. 禁止项确认

已验证：

- 未修改 ASK 业务代码。
- 未迁移 ASK Git root。
- 未修改 Hermes core。
- 未写 Hermes internal DB。
- 未创建真实 worker。
- 未触发 Gateway 自动派发 coder。
- 未扩大 coder 并发。
- 未 push / merge / publish。
- 未 auto commit。
- 未把 `/Users/hula/workspace` 当成普通业务项目。

## 9. 顾问复核

Gemini CLI 只读复核结论：

- P5a 可按 “Feishu adapter runtime entry + P4 core reused + dry-run/manual dispatch” 收口。
- 未发现把项目管理逻辑写死到 Feishu 的证据；Feishu adapter 只做协议转换，路由在 P4 core。
- 未发现 worker/Gateway auto-dispatch、Hermes core/internal DB 风险。

Claude CLI 本次运行 exit=0，但输出为计划/工具调用样式文本，没有给出可直接采纳的 verdict；因此本报告不把它计入明确共识，只记录为未形成直接结论。

## 10. 未覆盖项与 P5b 前置限制

P5b 前必须继续保留以下限制：

- 继续 manual dispatch；不得自动派发 coder。
- 当前 adapter 以本地文件 JSON/JSONL + `flock` 做小流量验证；若扩大流量，需要重新设计持久化状态、审计、锁与并发模型。
- 当前白名单是静态配置；P5b 若面向多人真实使用，需要接入用户/项目 ACL。
- 当前只支持项目管理命令；不支持项目业务执行、worker 创建、Kanban 写入、真实 Gateway dispatch。
- 当前未处理真实 Feishu 签名校验、challenge 校验、token 校验、重试幂等与 HTTP server 生命周期；P5b 若接生产 webhook 必须补齐。
- 当前没有 Slack/微信/Discord adapter；但 P4 core 可复用，未来只新增各自 channel adapter。
