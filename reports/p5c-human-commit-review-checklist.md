# P5c Human Commit Review Checklist

项目：Multi-Agent Orchestration System
输入报告：`/Users/hula/workspace/multiagent-orchestration-system/reports/p5c-commit-sequence-review-guide.md`
目的：供人工 reviewer 快速判断是否批准按 3 个 commit 创建**本地提交**

## 最终判断
- [ ] **APPROVED_FOR_LOCAL_COMMIT**
- [ ] **NEEDS_FIX_BEFORE_COMMIT**

---

## 1) `feat(core): add project registry and gateway routing foundation`

**应包含文件类型**
- `config/*.yaml`
- `templates/*.md`
- `scripts/gateway/*.rb`
- `scripts/validation/*.rb`
- `reports/*.md`（仅基础路由/registry 相关）

**重点审阅问题**
- 仅包含 project registry / gateway routing / task guard 的基础骨架？
- 没有提前引入 Feishu 入口、conversation adapter 或 live integration？
- 验证脚本是否只读、无写状态副作用？

**必跑验证**
- `ruby -c scripts/gateway/project-router.rb`
- `ruby -c scripts/validation/verify-task-guard-project-registry.rb`
- `ruby -c scripts/validation/verify-gateway-project-routing.rb`
- `ruby scripts/validation/verify-task-guard-project-registry.rb`
- `ruby scripts/validation/verify-gateway-project-routing.rb`

**不应包含文件**
- `config/feishu-command-adapter.yaml`
- `templates/channel-agnostic-conversation-adapter.md`
- `scripts/conversation/project-conversation-router.rb`
- `scripts/adapters/feishu/*`
- `reports/p3-gateway-project-routing-report.md`
- `reports/p4-channel-agnostic-conversation-adapter-report.md`
- `reports/p5a-feishu-command-ingress-report.md`
- `reports/p5b-feishu-webhook-security-readiness-report.md`
- `reports/p5c-feishu-limited-live-integration-report.md`

---

## 2) `feat(feishu): add command ingress, security gates, and live-limited integration`

**应包含文件类型**
- `config/*.yaml`
- `templates/*.md`
- `scripts/conversation/*.rb`
- `scripts/adapters/feishu/*.rb`
- `scripts/validation/*.rb`
- `reports/*.md`（仅 Feishu / conversation / security 相关）

**重点审阅问题**
- `config/feishu-command-adapter.yaml` 是否仅用环境变量，不含明文 secret/token/key？
- `scripts/adapters/feishu/*` 是否只在 Feishu 入口层，不触达 ASK 业务代码或 Hermes core？
- conversation router 是否保持 channel-agnostic，不直接触发 worker / auto-dispatch？
- 验证是否覆盖入口、签名/安全门、限流、幂等、禁用开关、回归链路？

**必跑验证**
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

**不应包含文件**
- `config/projects.yaml`（若已在 commit 1 纳入）
- `templates/a2a-work-order-protocol.md`
- `templates/gateway-project-routing-gate.md`
- `templates/task-guard-project-registry-gate.md`
- `scripts/gateway/project-router.rb`
- `reports/project-overlay-registry-implementation-report.md`
- `reports/p1-reporter-project-routing-report.md`
- `reports/p2-blocked-forbidden-paths-diagnosis.md`
- `reports/p2-task-guard-project-registry-report.md`
- `reports/post-upgrade-project-management-plan.md`

---

## 3) `docs: add P0-P5c closeout and review artifacts`

**应包含文件类型**
- `reports/*.md`
- 可选 `state/conversations/*.json`（仅审阅样本）

**重点审阅问题**
- 是否全部是阶段总结 / 审计 / 收口 / 审阅指南？
- 是否明确排除 runtime state、logs、validation evidence？
- 是否没有把文档包装成实现代码或运行态配置？

**必跑验证**
- `ruby -e 'puts File.exist?("reports/p5c-closeout-packaging-report.md")'`
- `ruby -e 'puts File.exist?("reports/p5c-commit-whitelist-report.md")'`
- `ruby -e 'puts File.exist?("reports/p5c-commit-sequence-review-guide.md")'`
- `git status --short`

**不应包含文件**
- `config/*`
- `templates/*`
- `scripts/*`
- `reports/validation-evidence/*`
- `logs/feishu-adapter/*`
- `hermes-tasks/post-upgrade-project-management-plan.md`
- 任何 ASK 业务代码、Hermes core、Hermes internal DB 文件

---

## 禁止提交项
- `logs/`
- runtime state（`state/conversations/*` 中的运行样本、锁、状态文件）
- `reports/validation-evidence/`
- 临时任务文档（如 `hermes-tasks/*.md`）
- secret / token / credential
- ASK / Hermes core / internal DB 文件

---

## 最终判断格式
- **APPROVED_FOR_LOCAL_COMMIT**：三组 commit 都通过审阅，且禁止提交项未进入任一 commit。
- **NEEDS_FIX_BEFORE_COMMIT**：任一组存在越界文件、明文凭证、验证缺失、或提交范围混杂。
