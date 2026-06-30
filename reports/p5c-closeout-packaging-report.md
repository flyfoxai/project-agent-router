# P5c Closeout Packaging Report

项目：Multi-Agent Orchestration System
范围：P0-P5c 收口，不进入 P5d live trial

## 1. 当前 git status

```text
## main
 M templates/a2a-work-order-protocol.md
?? config/
?? hermes-tasks/
?? reports/ask-dirty-state-resolution-audit.md
?? reports/ask-gitignore-dirty-audit.md
?? reports/ask-gitignore-minimal-fix-report.md
?? reports/ask-gitignore-playwright-commit-prep-report.md
?? reports/ask-phase5-reverse-residue-cleanup-report.md
?? reports/hermes-project-boundary-and-management-audit.md
?? reports/p1-reporter-project-routing-report.md
?? reports/p2-blocked-forbidden-paths-diagnosis.md
?? reports/p2-task-guard-project-registry-report.md
?? reports/p3-gateway-project-routing-report.md
?? reports/p4-channel-agnostic-conversation-adapter-report.md
?? reports/p5a-feishu-command-ingress-report.md
?? reports/p5b-feishu-webhook-security-readiness-report.md
?? reports/p5c-feishu-limited-live-integration-report.md
?? reports/post-upgrade-project-management-plan.md
?? reports/project-overlay-registry-implementation-report.md
?? reports/validation-evidence/
?? scripts/
?? state/
?? templates/channel-agnostic-conversation-adapter.md
?? templates/gateway-project-routing-gate.md
?? templates/task-guard-project-registry-gate.md
!! logs/
```

补充：
- `git diff --name-status` 目前只显示 `M	templates/a2a-work-order-protocol.md`。
- `logs/` 已被 gitignore，属于本地证据区，不在提交面。

## 2. P0-P5c 新增/修改文件清单

### config
- `config/projects.yaml`
- `config/feishu-command-adapter.yaml`

### templates
- `templates/a2a-work-order-protocol.md`
- `templates/channel-agnostic-conversation-adapter.md`
- `templates/gateway-project-routing-gate.md`
- `templates/task-guard-project-registry-gate.md`

### scripts
- `scripts/gateway/project-router.rb`
- `scripts/conversation/project-conversation-router.rb`
- `scripts/adapters/feishu/feishu-command-adapter.rb`
- `scripts/adapters/feishu/feishu-webhook-security-gate.rb`
- `scripts/adapters/feishu/feishu-webhook-server.rb`

### validation
- `scripts/validation/verify-task-guard-project-registry.rb`
- `scripts/validation/verify-gateway-project-routing.rb`
- `scripts/validation/verify-channel-agnostic-conversation-adapter.rb`
- `scripts/validation/verify-p5a-feishu-command-ingress.rb`
- `scripts/validation/verify-p5b-feishu-webhook-security-readiness.rb`
- `scripts/validation/verify-p5c-feishu-limited-live-integration.rb`

### reports
- `reports/project-overlay-registry-implementation-report.md`
- `reports/p1-reporter-project-routing-report.md`
- `reports/p2-blocked-forbidden-paths-diagnosis.md`
- `reports/p2-task-guard-project-registry-report.md`
- `reports/p3-gateway-project-routing-report.md`
- `reports/p4-channel-agnostic-conversation-adapter-report.md`
- `reports/p5a-feishu-command-ingress-report.md`
- `reports/p5b-feishu-webhook-security-readiness-report.md`
- `reports/p5c-feishu-limited-live-integration-report.md`
- `reports/post-upgrade-project-management-plan.md`
- `reports/hermes-project-boundary-and-management-audit.md`
- `reports/ask-dirty-state-resolution-audit.md`
- `reports/ask-gitignore-dirty-audit.md`
- `reports/ask-gitignore-minimal-fix-report.md`
- `reports/ask-gitignore-playwright-commit-prep-report.md`
- `reports/ask-phase5-reverse-residue-cleanup-report.md`
- `reports/validation-evidence/*`（原始命令输出证据，不建议纳入 commit）

### state
- `state/conversations/sample-state.json`
- `state/conversations/p4-validation-state.json`
- `state/conversations/p5a-input-msg-1.json`
- `state/conversations/p5a-input-msg-2.json`
- `state/conversations/p5a-input-msg-3.json`
- `state/conversations/p5a-input-msg-4.json`
- `state/conversations/p5a-input-msg-6.json`
- `state/conversations/p5a-input-msg-rate-0.json`
- `state/conversations/p5a-input-msg-rate-1.json`
- `state/conversations/p5a-input-msg-rate-2.json`
- `state/conversations/p5a-input-msg-rate-3.json`
- `state/conversations/p5a-input-msg-rate-4.json`
- `state/conversations/p5a-rate-limit-state.json`
- `state/conversations/p5a-validation-state.json`
- `state/conversations/p5a-validation.lock`
- `state/conversations/p5b-body.json`
- `state/conversations/p5b-headers.json`
- `state/conversations/p5b-idempotency-state.json`
- `state/conversations/p5b-rate-limit-state.json`
- `state/conversations/p5b-validation-state.json`
- `state/conversations/p5b-validation.lock`
- `state/conversations/p5c-idempotency-state.json`
- `state/conversations/p5c-rate-limit-state.json`
- `state/conversations/p5c-validation-state.json`
- `state/conversations/p5c-validation.lock`
- `state/conversations/feishu-command-adapter-inner.lock`

### logs
- `logs/feishu-adapter/p5a-validation-audit.jsonl`
- `logs/feishu-adapter/feishu-command-adapter-inner-audit.jsonl`
- `logs/feishu-adapter/p5b-validation-audit.jsonl`
- `logs/feishu-adapter/p5c-validation-audit.jsonl`

### task/ledger
- `hermes-tasks/post-upgrade-project-management-plan.md`
- external ledger: `~/.hermes/task_guard/tasks.json`（已更新，不在仓库内，也不应提交）

## 3. 建议纳入 commit 的文件

### 建议纳入 commit 的核心交付
- `config/projects.yaml`
- `config/feishu-command-adapter.yaml`
- `templates/a2a-work-order-protocol.md`
- `templates/channel-agnostic-conversation-adapter.md`
- `templates/gateway-project-routing-gate.md`
- `templates/task-guard-project-registry-gate.md`
- `scripts/gateway/project-router.rb`
- `scripts/conversation/project-conversation-router.rb`
- `scripts/adapters/feishu/feishu-command-adapter.rb`
- `scripts/adapters/feishu/feishu-webhook-security-gate.rb`
- `scripts/adapters/feishu/feishu-webhook-server.rb`
- `scripts/validation/verify-task-guard-project-registry.rb`
- `scripts/validation/verify-gateway-project-routing.rb`
- `scripts/validation/verify-channel-agnostic-conversation-adapter.rb`
- `scripts/validation/verify-p5a-feishu-command-ingress.rb`
- `scripts/validation/verify-p5b-feishu-webhook-security-readiness.rb`
- `scripts/validation/verify-p5c-feishu-limited-live-integration.rb`
- `reports/project-overlay-registry-implementation-report.md`
- `reports/p1-reporter-project-routing-report.md`
- `reports/p2-task-guard-project-registry-report.md`
- `reports/p3-gateway-project-routing-report.md`
- `reports/p4-channel-agnostic-conversation-adapter-report.md`
- `reports/p5a-feishu-command-ingress-report.md`
- `reports/p5b-feishu-webhook-security-readiness-report.md`
- `reports/p5c-feishu-limited-live-integration-report.md`
- `reports/post-upgrade-project-management-plan.md`
- `reports/hermes-project-boundary-and-management-audit.md`

### 可选纳入 commit 的 fixture
- `state/conversations/sample-state.json`
- `state/conversations/p4-validation-state.json`

说明：如果团队希望保留 P4 作为可复现实例，这两个 fixture 可以纳入；如果目标是最小提交面，也可以先不提交。

## 4. 建议不纳入 commit、只保留本地证据的文件

### 明确不建议提交
- `reports/validation-evidence/*`
- `logs/feishu-adapter/*`
- `state/conversations/p5a-*`
- `state/conversations/p5b-*`
- `state/conversations/p5c-*`
- `state/conversations/feishu-command-adapter-inner.lock`
- `hermes-tasks/post-upgrade-project-management-plan.md`

### 也建议暂不纳入本次 commit 的历史审计类报告
- `reports/ask-dirty-state-resolution-audit.md`
- `reports/ask-gitignore-dirty-audit.md`
- `reports/ask-gitignore-minimal-fix-report.md`
- `reports/ask-gitignore-playwright-commit-prep-report.md`
- `reports/ask-phase5-reverse-residue-cleanup-report.md`

原因：这些更像本地调试/审计/证据材料，适合作为收口包附件，而不是 P0-P5c 核心交付面。

## 5. 是否存在 secret 或敏感信息风险

结论：**没有发现仓库内明文 secret。风险为低到中。**

依据：
- `config/feishu-command-adapter.yaml` 只保存环境变量名，不保存真实 token/key。
- 配置中明确要求生产 secret 来自仓库外部：`env_only_for_live_limit` / `configure production secret source outside repository`。
- P5c 最新验证摘要中包含 `P5C_SECRET_NOT_WRITTEN_TO_REPO=YES`。

仍需注意：
- `state/conversations/p5b-body.json`、`state/conversations/p5b-headers.json` 等文件是测试输入/输出证据，可能包含用户 ID、header 样本、请求体样本，建议保持本地，不进 commit。
- `logs/feishu-adapter/*` 也可能记录命令或审核字段，同样不建议提交。

## 6. 是否存在 ASK / Hermes core / internal DB 越界修改

结论：**未发现本次 P0-P5c 收口对 ASK 业务代码、Hermes core 或 Hermes internal DB 的越界修改。**

依据：
- 最新验证结果中：
  - `ASK_CODE_MODIFIED=NO`
  - `HERMES_CORE_MODIFIED=NO`
  - `HERMES_INTERNAL_DB_MODIFIED=NO`
- `git status` 里当前仓库修改集中在 multiagent-orchestration-system 的 config/templates/scripts/reports/state/logs/ledger 相关文件。
- `git diff --name-status` 当前仅显示 `templates/a2a-work-order-protocol.md` 为已修改跟踪文件。

补充说明：
- 历史上有一份 P2 独立报告记录过 ASK 父仓库脏态，但那是外部历史状态，不是本次收口在本仓库内造成的修改。
- 最新 P5c 归并回归里，P2/P3/P4/P5a/P5b/P5c 均已通过。

## 7. P2 / P3 / P4 / P5a / P5b / P5c 最新验证摘要

### P2
- 最新 P5c 归并回归：`P2_REGRESSION_PASSED=YES`
- 说明：这表示当前收口验证链路内的 P2 约束已通过。

### P3
- `P3_VALIDATION_PASSED=YES`
- `summary.total=22 passed=22 failed=0`
- 关键结果：gateway dry-run route、project registry 读取、禁止 worker auto-dispatch、禁止 ASK 代码修改均通过。

### P4
- `P4_VALIDATION_PASSED=YES`
- `P4_SUMMARY total=30 passed=30 failed=0`
- 关键结果：conversation-core、channel isolation、current/default/project list/use/clear、低置信度阻断均通过。

### P5a
- `P5A_EXIT=0`
- `P5A_SUMMARY total=25 passed=25 failed=0`
- 关键结果：Feishu adapter 接入、白名单、输入校验、rate limit、audit log、disable switch、state lock 通过。

### P5b
- `P5B_EXIT=0`
- `P5B_SUMMARY total=28 passed=28 failed=0`
- 关键结果：challenge、token/signature 校验、幂等、ACL、禁用开关、HTTP lifecycle/readiness 通过。

### P5c
- `P5C_HTTP_SERVER_ENTRY_READY=YES`
- `P5C_FEISHU_CHALLENGE_LIVE_READY=YES`
- `P5C_FEISHU_CREDENTIAL_ENV_READY=YES`
- `P5C_SECRET_NOT_WRITTEN_TO_REPO=YES`
- `P5C_DISABLE_SWITCH_READY=YES`
- `P5C_WHITELIST_READY=YES`
- `P5C_PROJECT_ACL_READY=YES`
- `P5C_RETRY_IDEMPOTENCY_READY=YES`
- `P5C_AUDIT_LOG_READY=YES`
- `P5C_RATE_LIMIT_LOCK_READY=YES`
- `P5C_ALLOWED_COMMANDS_ONLY=YES`
- `P5C_CONVERSATION_CORE_REUSED=YES`
- `P5C_WORKER_AUTO_DISPATCH_TRIGGERED=NO`
- `P5C_GATEWAY_AUTO_DISPATCH_TRIGGERED=NO`
- `P5B_REGRESSION_PASSED=YES`
- `P5A_REGRESSION_PASSED=YES`
- `P4_REGRESSION_PASSED=YES`
- `P3_REGRESSION_PASSED=YES`
- `P2_REGRESSION_PASSED=YES`
- `P5C 全量：35/35 通过`

## 8. P5d 小流量真实联调前置条件清单

1. **明确授权**：用户确认允许进入真实 Feishu live trial。
2. **真实凭据就绪**：
   - `FEISHU_VERIFICATION_TOKEN`
   - `FEISHU_ENCRYPT_KEY`
   - 生产 secret 必须来自仓库外部环境变量/安全配置。
3. **真实 challenge / signature 复核**：用真实 Feishu app 事件确认 challenge 和签名公式。
4. **回滚/禁用开关可用**：`FEISHU_WEBHOOK_DISABLED=1` / `--disabled` / `config.webhook_enabled=false`。
5. **白名单与项目 ACL 完整**：明确允许的用户、项目和命令集不扩大。
6. **只允许窄命令集**：仍仅限以下命令：
   - `/project list`
   - `/project current`
   - `/project use <project_id>`
   - `/project default <project_id>`
   - `/project clear`
   - `/system status`
   - `/orchestration status`
7. **观察与审计**：确认 audit log、rate limit、idempotency、lock/state 路径在生产环境可读写。
8. **流量策略**：只做小流量/手动点对点联调，不开自动派发，不放大 coder 并发，不进入全量接入。
9. **运行环境**：真实 webhook 地址、网络、证书、端口、回调 URL 均在 Feishu 侧完成配置确认。
10. **验收口径**：先验收 challenge、签名、禁用开关、白名单、ACL、回滚，再考虑扩大范围。

## 9. rollback / disable 操作说明

### 立即禁用
优先级从高到低：
1. `FEISHU_WEBHOOK_DISABLED=1`
2. 启动参数 `--disabled`
3. 配置 `config.webhook_enabled=false`

### 运行时回滚
- 停掉 WEBrick / live server 进程，采用 graceful SIGTERM。
- 在 Feishu 侧关闭回调或切换到备用/空回调地址。
- 保留本地日志与 state 作为回滚证据，但不要提交这些文件。

### 代码回滚
- 如果只想回退本次 P5c 增量，优先撤销：
  - `scripts/adapters/feishu/feishu-webhook-server.rb`
  - `scripts/validation/verify-p5b-feishu-webhook-security-readiness.rb` 的验证修补
- 其余 P5a/P4/P3/P2 文件保持不动，避免误伤已验证的基础层。

### 预期效果
- 入口不可用，live 请求不再进入。
- 由于禁用开关优先，风险最小、恢复最快。

## 10. 结论

- P0-P5c 当前已形成可人工 review 的收口包。
- 最新验证链路显示 P2/P3/P4/P5a/P5b/P5c 均通过。
- 没有发现本次收口对 ASK/Hermes core/internal DB 的越界修改。
- 没有发现仓库内明文 secret；但 state/log/evidence 文件应保持本地，不纳入 commit。
- 当前不进入 P5d live trial；P5d 仅保留前置条件与回滚说明。
