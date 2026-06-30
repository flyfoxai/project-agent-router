# P5c Commit Sequence Review Guide

项目：Multi-Agent Orchestration System
输入依据：`/Users/hula/workspace/multiagent-orchestration-system/reports/p5c-commit-whitelist-report.md`
用途：把推荐的 3 个 commit 拆成可人工 review 的提交顺序、文件范围和审阅重点，便于后续人工决定是否真正提交
约束：本轮**不执行** commit / push / merge / release，不修改 `.gitignore`，不删除文件，不启动 P5d live trial，不创建 worker，不触发 Gateway 自动派发 coder，不修改 ASK 业务代码，不迁移 ASK Git root，不修改 Hermes core，不写 Hermes internal DB

## 1. 当前 git status --short

> 说明：以下是本次生成报告前的仓库快照。写入本报告后，`git status --short` 会额外多出本文件本身。

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
?? reports/p5c-commit-whitelist-report.md
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

补充：
- `logs/` 在当前仓库中已是 gitignored，因此未出现在上述状态里。
- 当前唯一 tracked 修改是 `templates/a2a-work-order-protocol.md`。

## 2. 推荐提交顺序

**推荐顺序：**

1. **Commit 1 — 基础配置与路由骨架**
2. **Commit 2 — conversation adapter 与 Feishu 入口**
3. **Commit 3 — 阶段报告与收口文档**

### 为什么按这个顺序
- 第 1 个 commit 先把基础配置、project registry、gateway routing、task guard 相关骨架落定。
- 第 2 个 commit 再进入 Feishu 入口、conversation adapter、验证脚本和安全边界。
- 第 3 个 commit 只放报告、审计、收口和评审文档，避免把实现代码和文档噪声混在一起。

---

## 3. Commit 1：基础配置与路由骨架

### commit message
`feat(core): add project registry and gateway routing foundation`

### 文件白名单
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

### 不应包含的文件
- `config/feishu-command-adapter.yaml`
- `templates/channel-agnostic-conversation-adapter.md`
- `scripts/conversation/project-conversation-router.rb`
- `scripts/adapters/feishu/*`
- `scripts/validation/verify-channel-agnostic-conversation-adapter.rb`
- `scripts/validation/verify-p5a-feishu-command-ingress.rb`
- `scripts/validation/verify-p5b-feishu-webhook-security-readiness.rb`
- `scripts/validation/verify-p5c-feishu-limited-live-integration.rb`
- `reports/p3-gateway-project-routing-report.md`
- `reports/p4-channel-agnostic-conversation-adapter-report.md`
- `reports/p5a-feishu-command-ingress-report.md`
- `reports/p5b-feishu-webhook-security-readiness-report.md`
- `reports/p5c-feishu-limited-live-integration-report.md`
- `reports/post-upgrade-project-management-plan.md`
- `reports/hermes-project-boundary-and-management-audit.md`
- `reports/p5c-closeout-packaging-report.md`
- `reports/p5c-commit-whitelist-report.md`
- `reports/p5c-commit-sequence-review-guide.md`
- `state/`、`reports/validation-evidence/`、`logs/`、`hermes-tasks/`

### 人工审阅重点
- `config/projects.yaml` 是否只包含项目 registry / 路由 / ACL 的基础信息，未夹带临时运行态数据。
- `templates/a2a-work-order-protocol.md` 是否只是工作协议模板，不含环境绑定或个人化一次性内容。
- `templates/gateway-project-routing-gate.md` 与 `templates/task-guard-project-registry-gate.md` 是否与现有项目边界一致。
- `scripts/gateway/project-router.rb` 是否只是 gateway 基础路由，不提前引入 Feishu 入口逻辑。
- `scripts/validation/*` 是否为只读验证脚本，不写入状态、不做提交副作用。
- 报告类文件是否只是证据与审计，不把临时调试信息写成长期决策。

### 必跑验证命令
- `ruby -c scripts/gateway/project-router.rb`
- `ruby -c scripts/validation/verify-task-guard-project-registry.rb`
- `ruby -c scripts/validation/verify-gateway-project-routing.rb`
- `ruby scripts/validation/verify-task-guard-project-registry.rb`
- `ruby scripts/validation/verify-gateway-project-routing.rb`
- 如项目已有统一脚本，可再补：`pnpm lint` / `pnpm test` / `pnpm type-check:all`

### 回滚影响
- 回滚后会失去项目 registry / gateway routing / task guard 的基础骨架。
- 若后续 commit 2 / 3 已依赖这些基础文件，回滚 1 会导致后续验证与说明文档失去支撑。
- 风险主要是“路由骨架被撤回后，后续 Feishu / conversation 相关逻辑无法解释或复现”。

---

## 4. Commit 2：conversation adapter 与 Feishu 入口

### commit message
`feat(feishu): add command ingress, security gates, and live-limited integration`

### 文件白名单
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

### 不应包含的文件
- `config/projects.yaml`（若已在 commit 1 纳入，则此处不应重复）
- `templates/a2a-work-order-protocol.md`
- `templates/gateway-project-routing-gate.md`
- `templates/task-guard-project-registry-gate.md`
- `scripts/gateway/project-router.rb`
- `reports/project-overlay-registry-implementation-report.md`
- `reports/p1-reporter-project-routing-report.md`
- `reports/p2-blocked-forbidden-paths-diagnosis.md`
- `reports/p2-task-guard-project-registry-report.md`
- `reports/post-upgrade-project-management-plan.md`
- `reports/hermes-project-boundary-and-management-audit.md`
- `reports/p5c-closeout-packaging-report.md`
- `reports/p5c-commit-whitelist-report.md`
- `reports/p5c-commit-sequence-review-guide.md`
- `state/`、`reports/validation-evidence/`、`logs/`、`hermes-tasks/`

### 人工审阅重点
- `config/feishu-command-adapter.yaml` 是否仅使用环境变量引用，不含明文 token / key / secret。
- `scripts/adapters/feishu/*` 是否严格限制在 Feishu 入口层，没有越权修改 ASK 业务代码或 Hermes core。
- `scripts/conversation/project-conversation-router.rb` 是否只做 channel-agnostic conversation 路由，不直接触发 worker / gateway auto-dispatch。
- `scripts/validation/*` 是否覆盖：入口、签名/安全门、限流、幂等、禁用开关、回归链路。
- `reports/p3/p4/p5a/p5b/p5c` 是否与实现文件一致，没有夸大验证范围。

### 必跑验证命令
- `ruby -c scripts/conversation/project-conversation-router.rb`
- `ruby -c scripts/adapters/feishu/feishu-command-adapter.rb`
- `ruby -c scripts/adapters/feishu/feishu-webhook-security-gate.rb`
- `ruby -c scripts/adapters/feishu/feishu-webhook-server.rb`
- `ruby -c scripts/validation/verify-channel-agnostic-conversation-adapter.rb`
- `ruby -c scripts/validation/verify-p5a-feishu-command-ingress.rb`
- `ruby -c scripts/validation/verify-p5b-feishu-webhook-security-readiness.rb`
- `ruby -c scripts/validation/verify-p5c-feishu-limited-live-integration.rb`
- `ruby scripts/validation/verify-channel-agnostic-conversation-adapter.rb`
- `ruby scripts/validation/verify-p5a-feishu-command-ingress.rb`
- `ruby scripts/validation/verify-p5b-feishu-webhook-security-readiness.rb`
- `ruby scripts/validation/verify-p5c-feishu-limited-live-integration.rb`

### 回滚影响
- 回滚后会失去 Feishu 命令入口、webhook 安全门、limited-live integration 以及 conversation adapter。
- 若 commit 3 已保留相关报告，回滚 2 会使报告与实现不一致。
- 风险主要是“入口和安全边界倒退”，这会直接影响后续 live 入口验证。

---

## 5. Commit 3：阶段报告与收口文档

### commit message
`docs: add P0-P5c closeout and review artifacts`

### 文件白名单
- `reports/post-upgrade-project-management-plan.md`
- `reports/hermes-project-boundary-and-management-audit.md`
- `reports/p5c-closeout-packaging-report.md`
- `reports/p5c-commit-whitelist-report.md`
- `reports/p5c-commit-sequence-review-guide.md`
- 可选：`state/conversations/sample-state.json`、`state/conversations/p4-validation-state.json`（仅当团队明确希望保留为审阅样本时）

### 不应包含的文件
- `config/*`
- `templates/*`
- `scripts/*`
- `reports/validation-evidence/*`
- `logs/feishu-adapter/*`
- `state/conversations/p5a-*`
- `state/conversations/p5b-*`
- `state/conversations/p5c-*`
- `state/conversations/*.lock`
- `hermes-tasks/post-upgrade-project-management-plan.md`
- 任何 ASK 业务代码、Hermes core、Hermes internal DB 文件

### 人工审阅重点
- 这些文档是否只是“阶段总结 / 审计 / 收口 / 审阅指南”，而不是伪装成实现代码。
- `p5c-closeout-packaging-report.md` 与 `p5c-commit-whitelist-report.md` 是否一致，是否把不应提交的 runtime state / logs / validation evidence 明确排除。
- `p5c-commit-sequence-review-guide.md` 是否把提交顺序讲清楚，且没有要求实际 commit。
- `post-upgrade-project-management-plan.md` 是否仍被当作运行态计划，而不是产品主干。

### 必跑验证命令
- `ruby -e 'puts File.exist?("reports/p5c-closeout-packaging-report.md")'`
- `ruby -e 'puts File.exist?("reports/p5c-commit-whitelist-report.md")'`
- `ruby -e 'puts File.exist?("reports/p5c-commit-sequence-review-guide.md")'`
- 如需交叉校验内容，可执行：`grep` 替代方案请用 `search_files` / `read_file` 读取关键段落
- 若团队要求最终检查，可再跑一次：`git status --short`

### 回滚影响
- 回滚后会失去 P0-P5c 的收口证据、审计结论和人工 review 指南。
- 对产品运行影响较小，但对后续交接、审阅和问题追溯影响很大。
- 这是“文档层回滚”，不应影响已存在的实现层，但会削弱可追溯性。

---

## 6. 明确哪些文件必须先暂不提交

以下文件 / 目录 **必须先暂不提交**：

### logs/
- `logs/feishu-adapter/p5a-validation-audit.jsonl`
- `logs/feishu-adapter/feishu-command-adapter-inner-audit.jsonl`
- `logs/feishu-adapter/p5b-validation-audit.jsonl`
- `logs/feishu-adapter/p5c-validation-audit.jsonl`

### runtime state
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

### validation evidence
- `reports/validation-evidence/*`

### 临时任务文档
- `hermes-tasks/post-upgrade-project-management-plan.md`
- 以及其他仅用于执行排队、阶段协调、临时跟踪的任务文档

### 备注
这些项之所以必须先暂缓，是因为它们属于运行态、证据态或阶段管理态，变化频繁、容易带来噪声，有些还可能包含敏感样本或锁状态。

---

## 7. 是否建议在真正 commit 前先改 `.gitignore`

**建议：后续可以考虑改，但本轮不要改。**

### 原因
- `state/`、`reports/validation-evidence/`、`logs/`、`hermes-tasks/*.md` 这些目录/文件类别，未来很可能需要更清晰的忽略策略。
- 但当前这次任务明确要求**不要修改 `.gitignore`**，因此只能给建议，不能执行。
- 如果团队后续决定把运行态样本和证据文件长期留在本地而不进版本库，那么 `.gitignore` 应该在单独 review 后再调整。

### 建议优先评审的规则候选
- `reports/validation-evidence/`
- `state/conversations/p5a-*`
- `state/conversations/p5b-*`
- `state/conversations/p5c-*`
- `state/conversations/*.lock`
- `hermes-tasks/*.md`（仅当确认这些都是临时任务文档时）

---

## 8. 是否发现 secret / token / credential 风险

**结论：未发现仓库内明文 secret / token / credential，风险低。**

### 依据
- `config/feishu-command-adapter.yaml` 只引用环境变量名，不存真实 token/key。
- 现有报告已明确说明生产 secret 需要从仓库外部注入。
- 当前白名单范围里没有看到要求把真实凭证写入仓库的证据。

### 仍需注意
- `state/conversations/p5b-body.json`、`state/conversations/p5b-headers.json` 可能包含样本请求体或请求头，可能有用户标识或测试敏感信息，因此不建议提交。
- `logs/feishu-adapter/*` 也不建议提交，因为运行日志可能带出敏感上下文。

---

## 9. 是否发现 ASK / Hermes core / internal DB 越界风险

**结论：未发现需要纳入 commit 的 ASK / Hermes core / internal DB 越界风险。**

### 依据
- 本次白名单只建议纳入当前仓库内的 config / templates / scripts / reports。
- 报告已明确写出：
  - `ASK_CODE_MODIFIED=NO`
  - `HERMES_CORE_MODIFIED=NO`
  - `HERMES_INTERNAL_DB_MODIFIED=NO`
- 未发现必须触碰 ASK 业务代码、Hermes core 或 internal DB 的证据。

---

## 10. 最终结论

**READY_FOR_HUMAN_COMMIT_REVIEW**

### 为什么是这个结论
- 提交顺序已拆分为 3 个清晰阶段。
- 每个 commit 都给出了文件白名单、排除项、审阅重点、验证命令和回滚影响。
- 已明确标出必须暂缓提交的目录/文件类别。
- 已明确 `.gitignore` 只建议后续评审，不在本轮修改。
- 已明确 secret 风险低，且未发现 ASK / Hermes core / internal DB 越界风险。

### 什么时候会变成 `BLOCKED_NEEDS_FIX`
如果后续人工 review 发现以下任一情况，则应改为 blocked：
- `config/feishu-command-adapter.yaml` 里存在明文 secret/token/key
- `scripts/adapters/feishu/*` 触达 ASK 业务代码或 Hermes core
- `state/`、`logs/`、`reports/validation-evidence/` 被要求正式纳入 commit
- 任何 commit 白名单与现有实现 / 验证不一致

---

## 11. 报告生成说明

- 本报告仅用于人工提交前审阅，不执行任何版本控制操作。
- 本报告与 `p5c-commit-whitelist-report.md` 配套使用。
- 若后续需要真正提交，请先由人工按本报告做最终决定，再单独执行 commit。
