# Project Agent Router 中文说明

Project Agent Router 用来帮助一个自动化系统同时管理多个项目，并且尽量避免把任务发到错误的项目里。

它维护一份简单的项目清单，读取用户指令，判断这条指令属于哪个项目，并在项目不明确或操作风险较高时停止继续执行。

默认行为比较保守：

- 可以识别和切换项目。
- 可以在一次对话中记住当前项目。
- 可以生成 dry-run 工作单。
- 可以接收一组受限的飞书命令。
- 不会自动创建 worker。
- 不会自动 push、merge、publish，也不会自动修改其他项目。
- 不会把密钥或真实凭据提交到仓库。

## 为什么需要它

当一个自动化入口同时服务多个项目时，模糊指令很容易带来风险。

例如：

- “继续做。”
- “检查这个项目。”
- “把这个 push 上去。”
- “切到另一个仓库。”

人可以根据上下文理解这些话，但自动化系统必须先确认项目和权限，否则就可能操作错仓库。

Project Agent Router 的作用是在真正执行之前增加一层项目感知能力：先判断这是哪个项目、路由是否足够明确、这个操作是否被允许。

## 当前支持什么

当前版本支持：

- 在 `config/projects.yaml` 中登记多个项目。
- 通过项目 ID 或别名显式选择项目。
- 记录当前对话里的 current project 和 default project。
- 在报告和工作单中加入项目头信息。
- 生成 dry-run 工作单。
- 接收用于项目管理的飞书命令。
- 对 webhook 做 token、签名、重复事件、频率限制、用户白名单和项目白名单检查。
- 用本地验证脚本检查主要路由和安全规则。

仓库当前包含两个示例项目条目：

- `ask`
- `project-agent-router`

你可以在 `config/projects.yaml` 中增加、替换或调整项目配置。

## 项目选择方式

路由器优先使用明确的信息。简单来说，它会按下面的顺序判断：

1. 用户是否直接写明了项目。
2. 用户是否使用了已登记的项目别名。
3. 当前对话中是否已有 current project。
4. 是否配置了 default project。
5. 这是否只是一个系统状态类问题。
6. 如果仍然无法确认，就停止并要求澄清。

这样的指令可以被路由：

```text
/project use project-agent-router
```

但这样的指令应该被阻断：

```text
继续做
```

核心目标是避免把任务发到错误的仓库或错误的项目。

## 飞书命令

飞书适配器默认只开放项目管理相关命令。

支持的命令形态包括：

```text
/project list
/project current
/project use <project_id>
/project default <project_id>
/project clear
/system status
/orchestration status
```

适配器会先检查用户、项目、命令内容、重复事件和频率限制，然后再调用项目对话路由。

真实的飞书 token、签名 key、app secret 或 API key 应来自环境变量或外部密钥系统，不应该写入仓库。

## 安全默认值

Project Agent Router 把路由视为执行前准备，而不是直接执行。

默认情况下：

- 禁止自动派发 worker。
- 禁止 Gateway 自动派发。
- 真实项目修改需要单独人工批准。
- 高风险 Git 操作需要明确授权。
- 低置信度路由会被阻断。
- runtime state 和 logs 不进入 Git。

这让它更适合作为自动化执行前的控制层，而不是一个默认会直接动手的执行平台。

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
```

本地运行时可能出现 `logs/`、`state/`、`reports/validation-evidence/` 或任务相关目录。这些内容默认不应提交。

## 快速开始

进入仓库：

```bash
cd /path/to/project-agent-router
```

检查 Ruby：

```bash
ruby --version
```

查看已登记项目：

```bash
cat config/projects.yaml
```

尝试一次路由：

```bash
ruby scripts/gateway/project-router.rb --input "use project-agent-router"
```

运行主要验证：

```bash
ruby scripts/validation/verify-task-guard-project-registry.rb
ruby scripts/validation/verify-gateway-project-routing.rb
ruby scripts/validation/verify-channel-agnostic-conversation-adapter.rb
ruby scripts/validation/verify-p5a-feishu-command-ingress.rb
ruby scripts/validation/verify-p5b-feishu-webhook-security-readiness.rb
ruby scripts/validation/verify-p5c-feishu-limited-live-integration.rb
```

## 添加一个项目

添加项目时，通常需要：

1. 在 `config/projects.yaml` 的 `projects` 下增加一条配置。
2. 设置稳定的 `project_id`。
3. 添加用户可能会输入的别名。
4. 设置工作目录和 Git root。
5. 定义是否只允许手动派发。
6. 添加受保护路径和禁止的 Git 操作。
7. 运行验证脚本。

项目名和别名应尽量清晰。只有能稳定区分项目，路由器才有价值。

## 当前状态

Project Agent Router 目前适合作为一个轻量、本地优先的项目路由控制层。

推荐工作流是：

1. 先识别项目。
2. 再确认操作。
3. 生成 dry-run 结果。
4. 在任何真实写入、push、merge、publish 或 worker 派发前，先请求人工批准。

## 后续方向

可能的后续工作包括：

- 增加 `LICENSE`。
- 为 Ruby 验证脚本增加 CI。
- 补充项目 registry schema 文档。
- 增加更多项目配置示例。
- 增加 CLI、GitHub Issues、Slack 或通用 webhook 等输入渠道。
- 在任何真实执行前增加审批流程。
