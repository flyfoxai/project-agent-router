# P5c Commit Whitelist Report

项目：Multi-Agent Orchestration System
用途：为后续将 P0-P5c 的正式工程产物纳入版本管理，提供人工 review 版 commit 白名单建议
约束：本轮**不执行** commit / push / merge / release，不修改 `.gitignore`，不删除文件，不启动 P5d live trial，不创建 worker，不触发 Gateway 自动派发 coder，不修改 ASK 业务代码，不迁移 ASK Git root，不修改 Hermes core，不写 Hermes internal DB

## 1. 当前 git status --short

> 说明：以下状态来自本轮检查时的仓库快照。若在本报告写入后重新执行 `git status --short`，会额外看到本报告自身 `reports/p5c-commit-whitelist-report.md`。

```text
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
?? reports/p5c-closeout-packaging-report.md
?? reports/p5c-feishu-limited-live-integration-report.md
?? reports/post-upgrade-project-management-plan.md
?? reports/project-overlay-registry-implementation-report.md
?? reports/validation-evidence/
?? scripts/
?? state/
?? templates/channel-agnostic-conversation-adapter.md
?? templates/gateway-project-routing-gate.md
?? templates/task-guard-project-registry-gate.md
```

补充观察：
- `logs/` 在当前仓库里是 gitignored，因此未出现在 `git status --short` 中。
- 目前唯一已跟踪修改是 `templates/a2a-work-order-protocol.md`。

## 2. 建议纳入 commit 的文件白名单

### 2.1 config

建议纳入：
- `config/projects.yaml`
- `config/feishu-command-adapter.yaml`

理由：
- `config/projects.yaml` 是项目 registry / 路由 / ACL 的基础配置，属于正式工程产物。
- `config/feishu-command-adapter.yaml` 是 Feishu 命令入口的正式配置，包含白名单、ACL、幂等、rate limit、禁用开关与生产前约束，属于核心运行配置。
- 这两类文件决定系统运行边界，不应继续停留在本地临时态。

### 2.2 templates

建议纳入：
- `templates/a2a-work-order-protocol.md`
- `templates/channel-agnostic-conversation-adapter.md`
- `templates/gateway-project-routing-gate.md`
- `templates/task-guard-project-registry-gate.md`

理由：
- `templates/a2a-work-order-protocol.md` 是工作协议模板，属于核心协作规范。
- `templates/channel-agnostic-conversation-adapter.md` 定义 channel 无关的 conversation adapter 约束，是 P4/P5 链路的正式规范。
- `templates/gateway-project-routing-gate.md` 是 gateway project routing gate 的规则模板，决定路由边界。
- `templates/task-guard-project-registry-gate.md` 是 task guard / project registry 的规则模板，决定任务注册与执行边界。

### 2.3 scripts/adapters

建议纳入：
- `scripts/adapters/feishu/feishu-command-adapter.rb`
- `scripts/adapters/feishu/feishu-webhook-security-gate.rb`
- `scripts/adapters/feishu/feishu-webhook-server.rb`

理由：
- 这三份脚本构成 Feishu 入口的正式实现面，分别对应命令入口、webhook 安全门、webhook server。
- 它们是 P5a-P5c 的核心执行产物，不应作为临时脚本保留。

### 2.4 scripts/conversation

建议纳入：
- `scripts/conversation/project-conversation-router.rb`

理由：
- 这是 channel-agnostic conversation adapter 的关键路由实现，属于 P4 正式工程产物。
- 它承接项目路由与对话隔离逻辑，是后续 P5 入口复用的基础。

### 2.5 scripts/gateway

建议纳入：
- `scripts/gateway/project-router.rb`

理由：
- 这是 gateway project routing 的核心实现，属于 P3 正式工程产物。
- 该路由是 task guard / conversation adapter / Feishu ingress 之前的基础层。

### 2.6 scripts/validation

建议纳入：
- `scripts/validation/verify-task-guard-project-registry.rb`
- `scripts/validation/verify-gateway-project-routing.rb`
- `scripts/validation/verify-channel-agnostic-conversation-adapter.rb`
- `scripts/validation/verify-p5a-feishu-command-ingress.rb`
- `scripts/validation/verify-p5b-feishu-webhook-security-readiness.rb`
- `scripts/validation/verify-p5c-feishu-limited-live-integration.rb`

理由：
- 这些验证脚本是 P0-P5c 的真实回归入口，证明工程产物可验证、可回归、可审计。
- 它们不是临时一次性测试脚本，而是阶段性验收的一部分。
- 保留它们有助于后续回归和人工复核。

### 2.7 core reports

建议纳入：
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
- `reports/p5c-closeout-packaging-report.md`

理由：
- 这些是 P0-P5c 阶段的正式报告、审计、验收与收口产物，属于可追溯文档链。
- 它们为后续 review、验收、交接和问题回溯提供证据。
- `reports/p5c-closeout-packaging-report.md` 是本次收口后的整理报告，建议作为审阅附件保留；是否纳入正式提交，可由团队最终决定，但从版本管理角度是可提交的。

### 2.8 docs / hermes-tasks

建议纳入：
- **本轮不建议纳入 `hermes-tasks/` 下的任务文档**

理由：
- `hermes-tasks/post-upgrade-project-management-plan.md` 更偏临时任务文档 / 运行态计划，不是正式工程产物主干。
- 如果团队希望在仓库内保留计划痕迹，可单独评审后再决定；本轮不建议放进正式 commit 白名单。

## 3. 建议排除 commit 的文件清单

### 3.1 logs

建议排除：
- `logs/feishu-adapter/p5a-validation-audit.jsonl`
- `logs/feishu-adapter/feishu-command-adapter-inner-audit.jsonl`
- `logs/feishu-adapter/p5b-validation-audit.jsonl`
- `logs/feishu-adapter/p5c-validation-audit.jsonl`

理由：
- 这些是运行日志 / 审计日志 / 证据日志，体积和噪音都可能增长。
- 它们更适合保留在本地证据区，而不是版本主干。
- 日志会频繁变化，不适合作为稳定 commit 内容。

### 3.2 runtime state

建议排除：
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

理由：
- 这些是 runtime state / fixture / lock / validation state，变化频繁、只反映一次运行时的上下文。
- 它们会污染版本历史，且通常不应该成为正式工程产物。
- 其中部分文件可能携带敏感 header / body 样本，不适合纳入版本主干。

### 3.3 validation evidence

建议排除：
- `reports/validation-evidence/*`

理由：
- 这是原始命令输出证据，不是产品逻辑或长期文档本体。
- 这类文件通常量大、噪声多、重现价值有限，更适合本地留存或外部证据归档。

### 3.4 临时任务文档

建议排除：
- `hermes-tasks/post-upgrade-project-management-plan.md`
- 以及其他仅用于执行排队、阶段协调、临时跟踪的任务文档

理由：
- 任务文档属于运行期管理材料，不是正式工程交付面。
- 它们会随着阶段推进快速过时，留在 commit 里会增加长期维护噪音。

## 4. 每个纳入文件的理由汇总

> 这里按类别汇总，人工 review 时建议重点确认“是否属于正式工程产物、是否会被长期依赖、是否属于基础层”。

- **config**：决定运行边界、权限、路由和安全策略，属于基础配置。
- **templates**：沉淀跨阶段复用的协议 / gate / adapter 规范，属于正式规则面。
- **scripts/adapters**：Feishu 入口的核心实现，属于产品主逻辑。
- **scripts/conversation**：channel-agnostic conversation 路由实现，属于项目路由主线。
- **scripts/gateway**：gateway 路由实现，是上游基础层。
- **scripts/validation**：回归与验收脚本，支撑可验证性。
- **core reports**：阶段结论、审计和收口文档，支撑可追溯性与交接。
- **docs / hermes-tasks**：本轮不建议纳入；如需保留，必须单独确认其长期价值。

## 5. 每个排除类别的理由汇总

- **logs**：运行噪声，频繁变化，适合本地证据区，不适合作为版本主干。
- **runtime state**：运行时上下文/锁/样本，变化快且可能含敏感内容，不应提交。
- **validation evidence**：原始输出证据，适合作为临时归档，不适合进入正式版本历史。
- **临时任务文档**：阶段管理材料，生命周期短，容易过时。

## 6. 是否需要新增或调整 .gitignore

结论：**建议后续考虑调整，但本轮不修改。**

推荐后续评审的候选规则：
- `reports/validation-evidence/`
- `state/conversations/p5a-*`
- `state/conversations/p5b-*`
- `state/conversations/p5c-*`
- `state/conversations/*.lock`
- `hermes-tasks/*.md`（如果团队确认这些都属于临时任务文档）

说明：
- 当前仓库里 `logs/` 已经被 gitignore，因此不在 `git status --short` 中。
- `state/` 与 `reports/validation-evidence/` 目前仍出现在 untracked 列表里，说明这两类内容很可能值得在后续加规则，但需要先确认团队是否希望它们全部排除或只排除部分模式。
- 本轮为了遵守约束，不做任何 `.gitignore` 修改。

## 7. 是否发现 secret / token / credential 风险

结论：**未发现仓库内明文 secret / token / credential。风险为低。**

依据：
- `config/feishu-command-adapter.yaml` 只引用环境变量名，不存真实 token/key。
- 该配置明确要求生产 secret 从仓库外部来源注入。
- P5c 关闭报告已验证 `P5C_SECRET_NOT_WRITTEN_TO_REPO=YES`。

仍需注意：
- `state/conversations/p5b-body.json`、`state/conversations/p5b-headers.json` 一类文件属于测试输入/输出证据，可能包含请求头、用户标识、样本 body，建议排除。
- `logs/feishu-adapter/*` 也不建议提交，因为可能记录运行时细节或审计痕迹。

## 8. 是否发现 ASK / Hermes core / internal DB 越界文件

结论：**未发现需要纳入 commit 的文件触碰 ASK 业务代码、Hermes core 或 Hermes internal DB。**

依据：
- P5c 关闭报告中已记录：
  - `ASK_CODE_MODIFIED=NO`
  - `HERMES_CORE_MODIFIED=NO`
  - `HERMES_INTERNAL_DB_MODIFIED=NO`
- 当前白名单集中在本仓库内的 config / templates / scripts / reports / state / logs / task 文档。
- 没有看到需要把 ASK 业务代码、Hermes core 或 internal DB 文件拉入本次白名单的证据。

## 9. 最终推荐 commit strategy

### 推荐结论
**建议分多个 commit，不建议单 commit。**

原因：
- P0-P5c 覆盖基础配置、路由层、conversation 层、Feishu ingress、验证脚本、阶段报告，逻辑跨度大。
- 分 commit 更便于 review、回滚和定位问题。
- 将“实现层”和“文档/验收层”拆开，能减少审阅噪声。

### 建议的 commit 切分

#### Commit 1：基础配置与路由骨架
建议包含：
- `config/projects.yaml`
- `templates/a2a-work-order-protocol.md`
- `templates/gateway-project-routing-gate.md`
- `templates/task-guard-project-registry-gate.md`
- `scripts/gateway/project-router.rb`
- `reports/project-overlay-registry-implementation-report.md`
- `reports/p1-reporter-project-routing-report.md`
- `reports/p2-blocked-forbidden-paths-diagnosis.md`
- `reports/p2-task-guard-project-registry-report.md`
- `scripts/validation/verify-task-guard-project-registry.rb`
- `scripts/validation/verify-gateway-project-routing.rb`

建议 message：
- `feat(core): add project registry and gateway routing foundation`

#### Commit 2：conversation adapter 与 Feishu 入口
建议包含：
- `config/feishu-command-adapter.yaml`
- `templates/channel-agnostic-conversation-adapter.md`
- `scripts/conversation/project-conversation-router.rb`
- `scripts/adapters/feishu/feishu-command-adapter.rb`
- `scripts/adapters/feishu/feishu-webhook-security-gate.rb`
- `scripts/adapters/feishu/feishu-webhook-server.rb`
- `scripts/validation/verify-channel-agnostic-conversation-adapter.rb`
- `scripts/validation/verify-p5a-feishu-command-ingress.rb`
- `scripts/validation/verify-p5b-feishu-webhook-security-readiness.rb`
- `scripts/validation/verify-p5c-feishu-limited-live-integration.rb`
- `reports/p3-gateway-project-routing-report.md`
- `reports/p4-channel-agnostic-conversation-adapter-report.md`
- `reports/p5a-feishu-command-ingress-report.md`
- `reports/p5b-feishu-webhook-security-readiness-report.md`
- `reports/p5c-feishu-limited-live-integration-report.md`

建议 message：
- `feat(feishu): add command ingress, security gates, and live-limited integration`

#### Commit 3：阶段报告与收口文档
建议包含：
- `reports/post-upgrade-project-management-plan.md`
- `reports/hermes-project-boundary-and-management-audit.md`
- `reports/p5c-closeout-packaging-report.md`
- `reports/p5c-commit-whitelist-report.md`

可选包含：
- `state/conversations/sample-state.json`
- `state/conversations/p4-validation-state.json`

建议 message：
- `docs: add P0-P5c closeout and review artifacts`

### 如果团队强烈偏好单 commit
- 可以合并，但不推荐。
- 单 commit message 可用：
  - `feat: add P0-P5c orchestration foundation, Feishu ingress, and verification artifacts`
- 缺点是审阅、回滚和问题定位成本更高。

## 10. 最终建议

- **提交白名单**：以 config / templates / scripts / core reports 为主。
- **排除项**：logs、runtime state、validation evidence、临时任务文档。
- **.gitignore**：建议后续评审补规则，但本轮不修改。
- **安全性**：未发现明文 secret/token/credential。
- **越界**：未发现需要纳入 commit 的 ASK / Hermes core / internal DB 文件。
- **提交策略**：建议分 3 个 commit，逻辑清晰、便于 review。
