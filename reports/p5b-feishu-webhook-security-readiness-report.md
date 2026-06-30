# P5b Feishu Webhook Security and Deployment Readiness Report

项目：Multi-Agent Orchestration System  
project_id：multiagent-orchestration-system  
生成时间：2026-06-29T15:26:19+08:00  
报告路径：`/Users/hula/workspace/multiagent-orchestration-system/reports/p5b-feishu-webhook-security-readiness-report.md`

## 1. 结论

P5b 可以按 **Feishu webhook security/deployment readiness dry-run** 收口。

本轮没有接生产全量 webhook，没有启动真实公网 HTTP server，没有创建 worker，没有触发 Gateway 自动派发，也没有修改 Hermes core / Hermes internal DB / ASK 业务代码。

P5b 完成的是生产接入前的安全与部署 readiness 层：

- Feishu challenge 校验 dry-run。
- Feishu token 校验 dry-run。
- Feishu request signature 校验 dry-run contract。
- HTTP server lifecycle plan。
- 部署开关与快速禁用开关。
- Feishu retry event idempotency。
- 用户 / 项目 ACL dry-run。
- 生产级 audit JSONL 字段补齐。
- rate limit / lock / state store 风险复核。
- 继续复用 P5a adapter 和 P4 conversation-core。
- 继续 manual dispatch，不创建真实 worker。

## 2. 本轮新增/修改文件

```text
config/feishu-command-adapter.yaml
scripts/adapters/feishu/feishu-webhook-security-gate.rb
scripts/validation/verify-p5b-feishu-webhook-security-readiness.rb
logs/feishu-adapter/p5b-validation-audit.jsonl
logs/feishu-adapter/feishu-command-adapter-inner-audit.jsonl
state/conversations/p5b-validation-state.json
state/conversations/p5b-idempotency-state.json
state/conversations/p5b-rate-limit-state.json
state/conversations/p5b-validation.lock
state/conversations/feishu-command-adapter-inner.lock
state/conversations/p5b-body.json
state/conversations/p5b-headers.json
reports/p5b-feishu-webhook-security-readiness-report.md
```

说明：`logs/feishu-adapter/p5b-*` 与 `state/conversations/p5b-*` 是项目内 dry-run 验证证据，不是 Hermes internal DB，也不是生产 webhook 状态。

## 3. 必填字段

```text
P5B_CHALLENGE_VERIFICATION_READY=YES
P5B_SIGNATURE_OR_TOKEN_VERIFICATION_READY=YES
P5B_HTTP_SERVER_LIFECYCLE_READY=YES
P5B_DISABLE_SWITCH_READY=YES
P5B_RETRY_IDEMPOTENCY_READY=YES
P5B_USER_PROJECT_ACL_READY=YES
P5B_AUDIT_LOG_READY=YES
P5B_RATE_LIMIT_LOCK_STATE_REVIEW_READY=YES
P5B_CONVERSATION_CORE_REUSED=YES
P5B_WORKER_AUTO_DISPATCH_TRIGGERED=NO
P5B_GATEWAY_AUTO_DISPATCH_TRIGGERED=NO
P5A_REGRESSION_PASSED=YES
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

## 4. 架构边界

P5b 新增 `scripts/adapters/feishu/feishu-webhook-security-gate.rb`，职责限定为 webhook security gate：

```text
Feishu HTTP-like body/headers dry-run input
  -> token/signature/challenge/idempotency/ACL/disable checks
  -> P5a Feishu command adapter
  -> P4 channel-agnostic conversation-core
  -> P3/P2 project routing dry-run
  -> Feishu reply payload
```

项目管理逻辑没有写进 P5b Feishu security gate；P5b 只做安全、部署 readiness、幂等和授权边界。

## 5. 安全与 readiness 实现

`config/feishu-command-adapter.yaml` 已升级到 version 2，并保留：

```text
manual_dispatch_only=true
worker_auto_dispatch_allowed=false
gateway_auto_dispatch_allowed=false
```

新增能力：

- `webhook_enabled`：部署级开关。
- `webhook_security.verification_token`：token 校验配置，当前为测试值。
- `webhook_security.encrypt_key`：signature dry-run contract 配置，当前为测试值。
- `webhook_security.signature_required=true`。
- `webhook_security.token_required=true`。
- `idempotency.enabled=true` 与 TTL。
- `user_project_acl`：用户 / 项目授权 dry-run。
- `deployment.mode=dry_run_http_lifecycle_plan`。
- `deployment.no_full_traffic=true`。

## 6. P5b 验证结果

```text
P5B_EXIT=0
P5B_SUMMARY total=28 passed=28 failed=0
AUDIT_LOG=/Users/hula/workspace/multiagent-orchestration-system/logs/feishu-adapter/p5b-validation-audit.jsonl
AUDIT_RECORD_COUNT=7
```

- challenge_verification: PASS; exit=0; result=challenge_verified; reason=challenge_verified
- signature_blocks_invalid: PASS; exit=22; result=blocked; reason=signature_verification_failed
- token_blocks_invalid: PASS; exit=21; result=blocked; reason=token_verification_failed
- valid_webhook_reuses_p4_core: PASS; exit=0; result=ok; reason=ok
- retry_idempotency_duplicate_event: PASS; exit=0; result=duplicate_ignored; reason=idempotent_replay
- user_project_acl_blocks_project: PASS; exit=24; result=blocked; reason=project_acl_denied
- disable_switch_blocks_webhook: PASS; exit=23; result=disabled; reason=webhook_disabled
- http_server_lifecycle_plan: PASS; exit=0; result=None; reason=None
- production_audit_required_fields: PASS; exit=0; result=None; reason=None
- rate_limit_lock_state_review: PASS; exit=0; result=None; reason=None

## 7. 回归验证

```text
P5A_EXIT=0
P5A_SUMMARY total=25 passed=25 failed=0

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
- 未直接接生产全量 webhook 流量。
- 未把项目管理逻辑写死到 Feishu。

## 9. 顾问复核

Gemini CLI 只读复核结论：

- P5b 可按 webhook security/deployment readiness dry-run 收口。
- 未发现自动派发 worker/Gateway、Hermes core/internal DB、ASK 业务代码风险。
- 未发现把项目管理逻辑写死到 Feishu 的证据。
- 生产前必须补真实 HTTP server、真实 Feishu 签名/Token/challenge 联调、secret 管理、分布式状态/锁/audit、观测与告警。

Claude CLI 只读复核结论：

- P5b dry-run contract 可收口，验证覆盖 challenge、signature/token、idempotency、ACL、lifecycle plan、audit 和回归。
- 未发现自动派发、Hermes core/internal DB 或 ASK 业务代码越界。
- Feishu 层只做 security gate 和 adapter，项目路由继续经 P5a/P4/P3/P2。
- Claude 输出中包含 plan-mode 样式文本和建议文件路径，未作为本项目证据写入；本报告以真实文件与验证 JSON 为准。

## 10. 生产前未覆盖项 / P5c 前置限制

P5b 是 readiness dry-run，不等于生产可全量接入。P5c 或生产前必须补齐：

1. **真实 HTTP server**
   - 当前只有 body/headers 文件模拟入口和 lifecycle plan。
   - 生产前需要实际 HTTP server / Rack / framework、TLS、healthz、readyz、graceful shutdown、部署回滚。

2. **真实 Feishu 联调**
   - 当前 token/signature/challenge 使用测试 token/key 和 dry-run contract。
   - 生产前必须用真实 Feishu app 的 `verification_token` / `encrypt_key` / 回调头联调。
   - 如 Feishu 实际启用加密消息，还必须补官方 encrypt/decrypt 流程校验。

3. **Secret 管理**
   - 当前配置里是测试值。
   - 生产前必须迁移到环境变量、KMS、Vault 或等价 secret source，不能把生产密钥写入仓库。

4. **状态、锁、幂等、限流生产化**
   - 当前为本地文件 JSON/JSONL + `File.flock`，只适合单机小流量 dry-run。
   - 多实例生产需要 Redis/DB/集中式日志/分布式锁或单实例队列。

5. **审计与观测**
   - 当前 audit 是项目内 JSONL。
   - 生产前需要集中日志、指标、报警、失败率/签名失败率/ACL 拒绝率监控。

6. **ACL 管理**
   - 当前 `user_project_acl` 是静态配置。
   - 生产前需要真实用户身份映射、项目 ACL 生命周期、授权变更审计。

7. **继续 manual dispatch**
   - P5b 不授权自动派发 coder。
   - 任何自动派发、worker 创建或 Gateway dispatch 都必须另开阶段、另行授权和验证。
