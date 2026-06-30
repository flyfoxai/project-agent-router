# Project Agent Router

Project Agent Router 是一个面向 Hermes / Jarvis 场景的多项目、多智能体编排治理原型。它目前聚焦于“项目边界识别、任务路由、人工确认、dry-run 调度、渠道适配、安全闸门和可审计验证”，而不是自动创建真实 worker 或自动修改业务项目。

当前仓库已整理为独立 Git 仓库，适合作为 GitHub 项目继续发布与演进。默认原则是：**先治理、先验证、先人工确认；不自动派发 coder/worker，不跨项目写入，不把 runtime state 或凭据提交到仓库。**

## 项目定位

本项目提供一套 Project Overlay Registry + Gateway routing + conversation-core + adapter 的治理层，用于把用户在 Feishu/Jarvis 等渠道发起的模糊任务转换为可审计、可阻断、可 dry-run 的项目上下文。

它解决的问题包括：

- 多个项目共用同一个 agent/gateway 时，如何确认“当前任务属于哪个项目”。
- 如何在任务报告、ledger、work order 中强制携带项目元数据。
- 如何阻断低置信度路由、危险 Git 操作和跨项目误写。
- 如何让渠道适配层只进入 dry-run/manual dispatch，而不是自动创建 worker。
- 如何在发布前用本地验证脚本确认核心治理规则仍然生效。

## 支持的项目管理能力

当前能力以本地文件、模板和验证脚本为主：

- 项目注册与项目边界描述。
- ASK 与 Project Agent Router 两个项目的路由元数据。
- 当前 Git root / 目标 Git root / Git root 状态记录。
- 项目级 reporter header 模板。
- task_guard evidence 字段规范。
- Gateway 任务入口前的项目识别与阻断规则。
- dry-run work order 模板。
- Feishu 命令入口的用户、项目、命令白名单。
- webhook security gate、幂等、速率限制和审计日志路径设计。
- 本地验证脚本覆盖 P2-P5c 的核心路径。

## Project Overlay Registry

核心配置位于：

```text
config/projects.yaml
```

该 registry 是一个 overlay fact layer，用于路由、报告和验证。它记录项目 ID、别名、业务根目录、当前 Git 根、目标 Git 根、默认 board、task_guard workspace、受保护路径、禁止 Git 操作和验证命令。

重要边界：

- overlay registry 不是 Hermes core 的原生项目数据库。
- 当 registry 与真实文件系统或 Git 状态冲突时，以实时检查结果为准。
- registry 不授权自动派发 worker，也不扩大 coder 并发。

## Gateway project routing

Gateway 路由模板与实现位于：

```text
templates/gateway-project-routing-gate.md
scripts/gateway/project-router.rb
```

路由优先级包括：

1. 显式 project_id。
2. 显式项目别名。
3. board slug。
4. workspace path。
5. current project。
6. default project。
7. system meta。
8. 无法确认时阻断并要求澄清。

Gateway 必须输出项目头字段，例如 project_id、board、workspace_path、git_root_status、dispatch_mode、routing_source 和 routing_confidence。

低置信度或跨项目风险任务必须阻断；禁止把“继续做”“派给 worker”“把它改了”等模糊输入直接转为真实 worker 执行。

## Channel-agnostic conversation-core

conversation-core 位于：

```text
templates/channel-agnostic-conversation-adapter.md
scripts/conversation/project-conversation-router.rb
```

它把渠道输入转换为项目感知的 conversation state，并保持渠道无关：

- 不把 Feishu、CLI 或未来渠道的细节写死到核心项目状态模型里。
- 通过 conversation state 保存当前项目、用户上下文、dry-run dispatch 信息。
- 通过 safe state path 规则限制 state 文件只能写入仓库内的 `state/conversations/`。
- 输出仍遵循人工确认和 dry-run 边界。

## Feishu adapter

Feishu 适配配置和实现位于：

```text
config/feishu-command-adapter.yaml
scripts/adapters/feishu/feishu-command-adapter.rb
scripts/adapters/feishu/feishu-webhook-security-gate.rb
scripts/adapters/feishu/feishu-webhook-server.rb
```

当前状态是 dry-run/manual dispatch：

- 支持白名单用户、白名单项目、白名单命令。
- 支持 `/project list`、`/project current`、`/project use <project_id>`、`/project default <project_id>`、`/project clear`、`/system status`、`/orchestration status` 等命令形态。
- webhook 安全层设计包含 token 校验、签名校验、时间戳容忍、challenge 事件、幂等和速率限制。
- 凭据来源应为环境变量或外部 secret store；仓库内只保存环境变量名，不保存真实 token/key。

## Dry-run/manual dispatch 设计

默认 dispatch policy：

```text
manual_dispatch_only: true
worker_auto_dispatch_allowed: false
gateway_auto_dispatch_allowed: false
```

含义：

- Gateway 可以解析、路由、报告和生成 dry-run work order。
- 适配器可以接收命令并给出可审计结果。
- 系统不得自动创建 coder worker、不得自动启动 Gateway 派发、不得绕过人工确认。
- 真正执行前必须有明确项目、明确范围、明确读写权限、明确验证命令和人工授权。

## 当前安全边界

当前仓库的安全边界包括：

- 不提交 `.env`、证书、私钥、真实 token、真实 API key。
- runtime state 写入 `state/`，默认不提交。
- 日志写入 `logs/`，默认不提交。
- 本地验证 evidence 写入 `reports/validation-evidence/`，默认不提交。
- Hermes 临时任务材料写入 `hermes-tasks/`，默认不提交。
- `*.lock` 默认不提交，避免本地运行锁污染仓库。
- ASK 项目业务代码、Hermes core、Gateway live dispatch、P5d live trial 均不属于本仓库默认发布动作。

发布前仍需人工确认：

- GitHub remote URL。
- LICENSE 类型。
- 是否提交 README、`.gitignore` 和发布准备报告。
- 是否保留/整理历史 reports。

## 禁止自动派发 worker 的默认原则

本项目的默认治理原则是：**解析不等于执行，路由不等于派发，dry-run 不等于真实 worker。**

因此：

- Gateway 自动派发 coder 默认禁止。
- Feishu 命令入口自动派发 worker 默认禁止。
- 低置信度项目识别必须澄清。
- 跨项目或高风险 Git 操作必须阻断。
- 没有真实 executor 证据时，不得声称 agent/worker 正在运行。

## 快速开始

### 1. 克隆或进入仓库

```bash
cd /path/to/project-agent-router
```

### 2. 检查 Ruby 可用

本项目当前验证脚本使用 Ruby 标准库：

```bash
ruby --version
```

### 3. 查看项目 registry

```bash
cat config/projects.yaml
```

### 4. 运行路由验证

```bash
ruby scripts/validation/verify-task-guard-project-registry.rb
ruby scripts/validation/verify-gateway-project-routing.rb
```

### 5. 运行 conversation / Feishu dry-run 验证

```bash
ruby scripts/validation/verify-channel-agnostic-conversation-adapter.rb
ruby scripts/validation/verify-p5a-feishu-command-ingress.rb
ruby scripts/validation/verify-p5b-feishu-webhook-security-readiness.rb
ruby scripts/validation/verify-p5c-feishu-limited-live-integration.rb
```

## 配置说明

### `config/projects.yaml`

定义项目 overlay registry，包括：

- `project_id`
- `display_name`
- `aliases`
- `business_root`
- `project_root`
- `current_git_root`
- `desired_git_root`
- `git_root_status`
- `task_guard_workspace`
- `dispatch`
- `protected_scopes`
- `validation`

### `config/feishu-command-adapter.yaml`

定义 Feishu 命令入口与 webhook 安全边界，包括：

- `manual_dispatch_only`
- `worker_auto_dispatch_allowed`
- `gateway_auto_dispatch_allowed`
- `allowed_user_ids`
- `allowed_commands`
- `allowed_project_ids`
- `webhook_security`
- `idempotency`
- `rate_limit`
- `state`
- `audit`
- `deployment`

其中 `webhook_security.verification_token_env` 和 `webhook_security.encrypt_key_env` 应指向环境变量名；不要把真实凭据写入配置文件。

## 验证命令

推荐发布前运行：

```bash
ruby scripts/validation/verify-task-guard-project-registry.rb
ruby scripts/validation/verify-gateway-project-routing.rb
ruby scripts/validation/verify-channel-agnostic-conversation-adapter.rb
ruby scripts/validation/verify-p5a-feishu-command-ingress.rb
ruby scripts/validation/verify-p5b-feishu-webhook-security-readiness.rb
ruby scripts/validation/verify-p5c-feishu-limited-live-integration.rb
```

Git 发布准备检查：

```bash
git rev-parse --show-toplevel
git status --branch --short
git log -3 --format='%H%x09%s'
git remote -v
git status --short
```

## 目录结构

```text
config/
  projects.yaml
  feishu-command-adapter.yaml
scripts/
  gateway/
    project-router.rb
  conversation/
    project-conversation-router.rb
  adapters/feishu/
    feishu-command-adapter.rb
    feishu-webhook-security-gate.rb
    feishu-webhook-server.rb
  validation/
    verify-*.rb
templates/
  a2a-work-order-protocol.md
  gateway-project-routing-gate.md
  task-guard-project-registry-gate.md
  channel-agnostic-conversation-adapter.md
reports/
  *.md
```

本地运行时可能出现但默认不提交：

```text
logs/
state/
reports/validation-evidence/
hermes-tasks/
```

## 后续路线图

建议后续按以下顺序推进：

1. 明确开源 LICENSE 并补充 `LICENSE` 文件。
2. 增加最小 CI，自动运行 6 条 Ruby validation scripts。
3. 把 dry-run work order 输出标准化为机器可读 JSON schema。
4. 将 Project Overlay Registry schema 固化并添加 schema validation。
5. 为 Feishu webhook live mode 增加真实凭据接入说明，但保持 secret 不入库。
6. 增加更多渠道 adapter，例如 CLI、GitHub Issue、Slack 或 Webhook generic adapter。
7. 在人工审批机制成熟后，再评估是否支持受限 worker dispatch；默认仍应保持禁止自动派发。

## 当前发布状态

本 README 是 GitHub publish preparation 的一部分。当前仓库已设置 GitHub remote：`git@github.com:flyfoxai/project-agent-router.git`；尚未 push。维护者仍需决定是否提交 README、`.gitignore`、配置/模板/脚本中的项目重命名更新和发布准备报告，然后再进入 push review。
