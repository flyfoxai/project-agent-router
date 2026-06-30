# 升级后项目管理正式规划报告：Project Overlay Registry / task_guard / Reporter / ASK Git Root

- 生成时间：2026-06-26 20:00:49 CST
- 规划角色：ASK总管（Hermes Agent / Jarvis）
- 正式报告路径：`/Users/hula/workspace/multiagent-orchestration-system/reports/post-upgrade-project-management-plan.md`
- 迁移底稿：`/Users/hula/workspace/multiagent-orchestration-system/hermes-tasks/post-upgrade-project-management-plan.md`
- 现有审计依据：`/Users/hula/workspace/multiagent-orchestration-system/reports/hermes-project-boundary-and-management-audit.md`
- 适用范围：ASK、父级 workspace、multiagent-orchestration-system 的项目边界治理规划
- 本轮性质：只写正式规划报告，不实施配置、数据库、源码、Git 迁移、registry 创建、Gateway 自动派发或 coder 并发调整

## 0. 字段化结论

```text
HERMES_VERSION_CONFIRMED=Hermes Agent v0.17.0 (2026.6.19) · upstream 0f81b0d4 · local a3fa02a5 (+12573 carried commits)
STRICT_PROJECT_REGISTRY_NATIVE_SUPPORT=NO
PROJECT_OVERLAY_REGISTRY_RECOMMENDED=YES
ASK_CAN_BE_REGISTERED_AS_PROJECT_NOW=YES
MULTIAGENT_CAN_BE_REGISTERED_AS_PROJECT_NOW=YES
ASK_GIT_ROOT_FIX_READY_TO_EXECUTE=NO
NEXT_STEP_REQUIRES_HUMAN_APPROVAL=YES
```

字段解释：

- `STRICT_PROJECT_REGISTRY_NATIVE_SUPPORT=NO`：当前只读检查未找到 Hermes 严格原生 Project Registry 的可用命令、配置文件或 schema 证据；现有能力更接近 profile / workspace / board / task_guard 的组合。
- `PROJECT_OVERLAY_REGISTRY_RECOMMENDED=YES`：建议先用只读 overlay registry 固化项目事实，再逐步接入执行系统。
- `ASK_CAN_BE_REGISTERED_AS_PROJECT_NOW=YES`：可以在 overlay registry 中登记 ASK 项目身份，但必须标明当前 Git root 仍是父级 `/Users/hula/workspace`。
- `MULTIAGENT_CAN_BE_REGISTERED_AS_PROJECT_NOW=YES`：multiagent 已是独立 Git 仓库，可直接登记为独立项目。
- `ASK_GIT_ROOT_FIX_READY_TO_EXECUTE=NO`：本轮不具备执行迁移条件；ASK 侧存在既有 dirty，且用户明确禁止 `.git` / `.gitignore` / 源码等变更。
- `NEXT_STEP_REQUIRES_HUMAN_APPROVAL=YES`：后续创建 registry 文件、改 task_guard schema、改 Reporter 模板或迁移 ASK Git root 都需要人工审批。

## 0.1 本轮不执行清单

本报告仅提供规划与验证，不执行以下动作：

- 不创建或修改 Hermes registry / profile / config / database。
- 不修改 ASK 源码、测试、`package.json`、`pnpm-lock.yaml`、`config/tools/.eslintrc.js`、`.gitignore`。
- 不迁移 `.git`，不执行 `git mv/rm/reset/checkout`。
- 不 commit、push、publish、merge。
- 不扩大 coder 并发，不触发 Gateway 自动派发。
- 不读取或写入任何凭据；凭据类内容统一 `[REDACTED]`。

## 1. 当前结论

当前问题不是单一 Git 问题，而是三类边界没有统一注册：

1. **业务项目边界**：ASK 的业务项目根是 `/Users/hula/workspace/ASK`；multiagent 的业务项目根是 `/Users/hula/workspace/multiagent-orchestration-system`。
2. **代码仓库边界**：ASK 当前 Git top-level 是 `/Users/hula/workspace`，目标应修复为 `/Users/hula/workspace/ASK`；multiagent 当前已是独立 Git 仓库。
3. **Hermes 执行边界**：Hermes profile、Kanban workspace/board、task_guard workspace、Reporter 汇报头当前没有统一 `project_id` 约束。

因此升级后的治理目标是：先建立轻量 `Project Overlay Registry` 作为只读事实层，再逐步让 `task_guard`、Reporter、Kanban/Dashboard/Gateway 从该 registry 解析项目身份；ASK Git root 修复单独走人工审批路线，不在本规划任务中执行。

## 2. 已确认依据

### 2.1 Hermes 官方操作 skill 与当前能力边界

已只读加载 Hermes 官方操作 skill `hermes-agent`（version `2.0.0`），关键依据如下：

- Hermes Agent 是 Nous Research 的开源 AI agent framework，可运行在终端、消息平台和 IDE；当前 Jarvis 实例对外身份是 Hermes Agent，不是底层模型本体。
- Hermes 支持 persistent memory、skills、multi-platform gateway、profiles、plugins、MCP、cron、webhook、custom tools、provider-agnostic model routing。
- CLI 依据包括：`hermes setup`、`hermes model`、`hermes config`、`hermes gateway`、`hermes kanban`、`hermes doctor`、`hermes chat --profile ... --worktree ...` 等。
- Profiles 是隔离 config / sessions / skills / memory 的实例边界，可表达角色和默认 cwd；但 profile 本身不是严格 project registry。
- Gateway 能把同一 agent 接到 Feishu/Telegram/Discord/Slack 等平台；因此 Feishu 汇报必须带项目头，避免跨项目任务在消息侧被误解。
- Skill 说明强调配置值进入 `config.yaml`、密钥进入 `.env`；本报告不写入任何凭据，若未来报告中出现 token/key/password/connection string，必须写作 `[REDACTED]`。

当前 live 证据补充：

- `HERMES_VERSION_CONFIRMED={hermes_ver}`
- 已检查 `hermes config --help`、`hermes kanban --help` 和本地实现命中；现阶段未发现可直接使用的严格原生 `Project Registry` 命令或 `projects.yaml` 配置。
- Kanban 支持 workspace / board / profile / run；task_guard 支持 workspace ledger；这些是项目管理能力底座，但还不是统一 project registry。

因此本规划采用保守结论：`STRICT_PROJECT_REGISTRY_NATIVE_SUPPORT=NO`，推荐先落 `Project Overlay Registry` 作为只读事实层，待人工审批后再接入 task_guard / Reporter / Kanban / Gateway。

### 2.2 ASK / SP / 并行规则

从 ASK steering 规则确认：

- `/sp.*` 是当前用户可见 SP 入口，不是 shell 命令；禁止回退旧版 SP 入口。
- 复杂任务必须先调查上下文、给出 3 到 6 步计划、完成计划内验证后再结束。
- 读文件、查状态、独立检查可并行；涉及同一文件编辑必须串行。
- 并行任务必须通过文件和验证证据流转，避免口头指挥与上下文丢失。
- 报告类输出在 ASK 内默认进入 `docs/reports/`；本次目标属于 multiagent 独立项目，因此写入其 `reports/` 正式报告目录。

### 2.3 现有审计报告证据

`reports/hermes-project-boundary-and-management-audit.md` 已确认：

- ASK：`business_root=/Users/hula/workspace/ASK`，当前 Git top-level 为 `/Users/hula/workspace`。
- multiagent：`/Users/hula/workspace/multiagent-orchestration-system` 已是独立 Git 仓库。
- Hermes default 与 ASK profiles 当前 `terminal.cwd` 均指向 ASK，不是跨项目 registry。
- Kanban `tasks` 表有 `workspace_path`、`tenant`、`dispatch_mode`、`session_id` 等字段，但没有 `project_id`。
- task_guard 旧审计时只登记 `/Users/hula/workspace` 与 `/Users/hula/workspace/ASK`，后来本任务已为 multiagent 写入独立 workspace key。
- 审计报告建议短期建立 registry，只读约定先行，逐步接入 Kanban / task_guard / Dashboard / Gateway。

### 2.4 A2A 迁移报告证据

`reports/a2a-assets-migration-report.md` 与 `reports/a2a-work-order-protocol-report.md` 已确认：

- A2A 模板和报告已复制到 `/Users/hula/workspace/multiagent-orchestration-system`。
- ASK 侧 `.tasks/` 本地副本保留，作为证据，不删除。
- A2A 协议要求五类消息：`WORK_ORDER`、`STATUS_UPDATE`、`HANDOFF`、`REVIEW_RESULT`、`HUMAN_REPORT`。
- 默认 dispatcher mode 是 `manual`；启用 Gateway 自动拾取前必须显式设置 `dispatch.mode=auto` 且 `gateway_allowed=true`。
- 禁止把 local merge gate、报告文件或本地 evidence 误报为 PR / CI / 发布完成。

### 2.5 multiagent 忽略规则

`/Users/hula/workspace/multiagent-orchestration-system/.gitignore` 当前忽略：

- OS/editor 文件：`.DS_Store`、swap、IDE 目录。
- 本地环境与证书：`.env`、`.env.*`、`*.pem`、`*.key`、`*.crt`，但保留 `!.env.example`。
- 日志与临时目录：`*.log`、`logs/`、`tmp/`、`temp/`。
- 依赖和构建缓存：`node_modules/`、`.cache/`、`dist/`、`build/`、`coverage/`。
- Hermes/local agent runtime：`.hermes-local/`、`.agent-runtime/`、`.sessions/`。

本规划不修改 `.gitignore`。

## 3. Project Overlay Registry 规划

### 3.1 定位

`Project Overlay Registry` 是 Hermes 运行态之上的轻量项目事实层，不替代 Git、profile、Kanban 或 task_guard，而是给它们提供统一解析入口。

短期形态建议为只读 YAML 或 JSON 文件；中期再接入 Dashboard / Gateway / task_guard；长期再考虑数据库表和 CLI 管理命令。

### 3.2 推荐字段

每个项目至少包含：

```yaml
projects:
  ask:
    project_id: ask
    display_name: ASK
    business_root: /Users/hula/workspace/ASK
    project_root: /Users/hula/workspace/ASK
    current_git_root: /Users/hula/workspace
    desired_git_root: /Users/hula/workspace/ASK
    git_root_status: needs_migration
    default_profile: ask-orchestrator
    reporter_profile: ask-reporter
    default_board: ask
    task_guard_workspace: /Users/hula/workspace/ASK
    owner_channel: feishu:oc_ee1b2aacf08072f0d1c3618adfb3a0b4
    forbidden_paths:
      - /Users/hula/workspace/ASK/.gitignore
      - /Users/hula/workspace/ASK/package.json
      - /Users/hula/workspace/ASK/pnpm-lock.yaml

  multiagent-orchestration-system:
    project_id: multiagent-orchestration-system
    display_name: Multi-Agent Orchestration System
    business_root: /Users/hula/workspace/multiagent-orchestration-system
    project_root: /Users/hula/workspace/multiagent-orchestration-system
    current_git_root: /Users/hula/workspace/multiagent-orchestration-system
    desired_git_root: /Users/hula/workspace/multiagent-orchestration-system
    git_root_status: independent
    default_profile: multiagent-orchestrator
    reporter_profile: multiagent-reporter
    default_board: multiagent-orchestration-system
    task_guard_workspace: /Users/hula/workspace/multiagent-orchestration-system
    owner_channel: feishu:oc_ee1b2aacf08072f0d1c3618adfb3a0b4
```

### 3.3 加载顺序

建议解析顺序：

1. 显式用户输入的 `project_id`。
2. 当前任务/ledger 中的 `project_id`。
3. 当前 cwd 命中的 `project_root` 或 `business_root`。
4. 当前 Git top-level 命中的 `current_git_root`。
5. Hermes profile 的 `terminal.cwd`。
6. 无法唯一解析时阻塞，并要求 ASK总管补充项目派工表。

### 3.4 冲突处理

- 如果 `project_root` 与 `current_git_root` 不一致，不能直接报错；应显示为 `git_root_status=needs_migration` 或 `parent_git_root`。
- 如果一个 Git root 覆盖多个业务项目，Reporter 和 task_guard 必须展示业务项目与 Git root 双字段。
- 如果一个任务写入不同项目仓库，必须拆成多个 project-scoped 子任务，或在 task_guard 中写 `source_project_id` 与 `target_project_id`。
- 如果 registry 与 live `git rev-parse` 不一致，以 live 结果为准，并把 registry 标记为待更新。

## 4. task_guard 改造规划

### 4.1 目标

`task_guard` 不应只以 `workspace_path` 隐式表示项目，而应显式记录：

- `project_id`
- `workspace_path`
- `git_root`
- `business_root`
- `source_project_id`
- `target_project_id`
- `evidence_paths`
- `forbidden_scope_checked`

### 4.2 短期落地

不改插件源码的短期方案：

1. 在 task title 或 evidence 中固定写入 `project_id=...; workspace_path=...; git_root=...`。
2. 跨项目任务在 ASK ledger 中只保留索引；目标项目 ledger 中保留真实执行状态。
3. 完成状态必须附带目标仓库 `git status --short` 与目标文件回读证据。
4. 对 ASK 任务，必须同时记录 `business_root=/Users/hula/workspace/ASK` 与 `git_root=/Users/hula/workspace`，直到 Git root 修复完成。

### 4.3 中期落地

插件或 ledger schema 可增加 project object：

```json
{
  "project_id": "ask",
  "workspace_path": "/Users/hula/workspace/ASK",
  "business_root": "/Users/hula/workspace/ASK",
  "git_root": "/Users/hula/workspace",
  "target_git_root": "/Users/hula/workspace/ASK",
  "registry_version": 1
}
```

### 4.4 验收标准

- 查询 ASK 项目任务时，不混入 multiagent 产物执行状态。
- 查询 multiagent 项目任务时，可找到本规划与后续 A2A 协议治理任务。
- 每个 completed task 都有目标项目文件路径、Git root、验证命令和证据。
- 如果 `workspace_path` 与 `git_root` 不一致，Reporter 明确显示，不静默吞掉。

## 5. Reporter 飞书项目头规划

### 5.1 目标

Reporter 发给飞书的每条项目汇报都必须先显示项目边界，避免把 ASK、父级 workspace、multiagent 仓库混说。

### 5.2 标准项目头

建议固定模板：

```text
项目：ASK
project_id：ask
业务根：/Users/hula/workspace/ASK
Git 根：/Users/hula/workspace（待修复为 /Users/hula/workspace/ASK）
task_guard workspace：/Users/hula/workspace/ASK
目标仓库：/Users/hula/workspace/multiagent-orchestration-system（如为跨项目任务）
执行角色：ASK总管 / 代码实现智能体 / 独立验证智能体
验证状态：已验证 / 待验证 / 阻塞
```

### 5.3 汇报规则

- ASK总管是唯一面对 Jarvis / 飞书用户的角色。
- 子角色只能作为 worker、后台命令、delegate_task 或顾问，不直接回复飞书用户。
- 汇报必须区分“已验证事实”“未验证假设”“阻塞点”“下一步”。
- 对跨项目任务，必须展示 `source_project_id` 与 `target_project_id`。
- 不得把本地报告、ledger 更新、local merge gate 说成 PR、CI、发布或远端完成。

## 6. ASK Git root 修复路线

### 6.1 当前状态

- ASK 业务根：`/Users/hula/workspace/ASK`
- ASK 当前 Git top-level：`/Users/hula/workspace`
- ASK 目标 Git top-level：`/Users/hula/workspace/ASK`
- 父级 workspace 仍有既有 dirty 状态，包括 ASK `.gitignore` modified 与 ASK 业务代码/测试 dirty。

### 6.2 本规划不执行的事项

本轮明确不执行：

- 不迁移 `.git`。
- 不修改 ASK `.gitignore`。
- 不修改 ASK 业务代码、测试、package、lock、ESLint 配置。
- 不 commit、push、publish、merge。
- 不触发 Gateway 自动派发 coder。
- 不扩大 coder 并发。

### 6.3 推荐修复阶段

#### 阶段 A：只读冻结与证据收集

1. 记录父级 workspace 和 ASK 的 `git status --short`、`git branch --show-current`、`git remote -v`。
2. 标出 ASK 内变更、ASK 外 sibling 变更、父级配置变更。
3. 识别哪些 dirty 状态属于用户业务工作，哪些属于历史迁移残留。
4. 生成不可逆操作前的 rollback plan。

#### 阶段 B：业务决策

需要老板确认：

1. ASK 是否必须成为独立 Git 仓库。
2. 父级 `/Users/hula/workspace` 是否继续作为聚合仓库、废弃仓库，还是仅作为普通目录。
3. ASK 历史提交是否需要完整保留。
4. multiagent 是否作为 sibling 独立仓库保留。

#### 阶段 C：迁移方案设计

可选方案：

1. **推荐：ASK 独立仓库迁移**：保留 ASK 历史或重建独立 history，把 `.git` 边界移动到 ASK 目录。
2. **保守：继续父级仓库，但 registry 显式记录 ASK 的 parent Git root**：风险低，但长期仍需 Reporter/task_guard 强提示。
3. **拆分：父级 workspace 只保留元仓库，ASK 与 multiagent 都用独立仓库**：治理清晰，但迁移成本最高。

#### 阶段 D：执行与回归

执行前必须另开任务并单独审批，验证至少覆盖：

- 主会话链路：ASK总管从 ASK cwd 执行状态检查。
- 委托链路：delegate_task worker 能正确识别 project_id 与 cwd。
- cheap route / 智能路由链路：如启用，必须验证不会落到父级 workspace。
- auxiliary 链路：辅助模型/工具读写路径必须显式 project-scoped。
- fallback 链路：主 provider 失败时不能丢失 project_id。
- 外部接入链路：Feishu / cron / MCP / Kanban / Gateway 的项目头与 ledger key 正确。

## 7. 分阶段实施计划

### P0：项目身份显式化

- 创建只读 `Project Overlay Registry` 草案。
- 为 ASK 与 multiagent 固定 `project_id`、`business_root`、`project_root`、`current_git_root`、`desired_git_root`。
- Reporter 汇报先使用项目头模板。
- task_guard evidence 固定写入三元组：`project_id + workspace_path + git_root`。

验收：任一汇报或 ledger 项都能看出“业务项目、目标仓库、验证仓库”。

### P1：执行系统接入

- task_guard schema 或 wrapper 增加显式 project 字段。
- Kanban board slug 与 `project_id` 对齐。
- Dashboard 展示 project header。
- Gateway 接单前校验 `project_id` 与 `workspace_path`。

验收：ASK 与 multiagent 任务不会互相污染 ledger、board、report。

### P2：Git root 修复

- 基于阶段 A-D 单独创建 ASK Git root 修复任务。
- 在干净窗口执行迁移或保守治理方案。
- 全链路回归后再把 ASK registry `git_root_status` 从 `needs_migration` 改为 `independent` 或 `parent_git_root_accepted`。

验收：ASK 的 Git root 状态与 registry、Reporter、task_guard、Kanban/Dashboard/Gateway 一致。

## 8. 风险与回退

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| registry 与真实 Git 状态漂移 | 汇报误导、误提交 | 每次完成前运行 `git rev-parse --show-toplevel` 并记录 evidence |
| task_guard 只看 workspace | 跨项目任务混入 ASK ledger | evidence 强制写 `project_id + git_root`，中期改 schema |
| Reporter 缺项目头 | 飞书用户误以为 ASK 业务代码被改 | 汇报首段固定显示项目头 |
| Gateway 自动派发 | coder 在错误项目写入 | 默认 manual，auto 需 `gateway_allowed=true` 与 worktree/lock 检查 |
| ASK Git root 迁移误操作 | 历史、dirty 状态或配置丢失 | 单独任务、人工审批、rollback plan、禁止本轮执行 |

## 9. 本轮完成标准

本规划任务完成时必须满足：

1. 只新增或修改 `reports/post-upgrade-project-management-plan.md`；旧 `hermes-tasks/post-upgrade-project-management-plan.md` 作为迁移底稿保留，不在本轮修改。
2. 不修改 ASK 业务代码、配置、`.gitignore`、`.git`。
3. 不修改 multiagent `.gitignore` 或 `.git`。
4. 不执行 commit / push / publish / merge。
5. 不扩大 coder 并发，不触发 Gateway 自动派发。
6. 用 `git status --short`、目标文件回读、禁止路径检查验证范围。

## 10. 下一步建议

1. 将本文件作为 P0 项目管理改造的输入文档。
2. 单独创建 `Project Overlay Registry` 草案任务，产物建议放在 multiagent 项目内的 `config/`、`templates/` 或后续确认的治理目录，但需先经人工审批确认路径规范。
3. 单独创建 task_guard schema/wrapper 改造任务，先做兼容旧 ledger 的非破坏性扩展。
4. 单独创建 Reporter 项目头任务，先从飞书汇报模板接入，不改业务代码。
5. ASK Git root 修复必须另开高风险审批任务，先只读冻结，再讨论迁移方案。


## 11. 审计报告原文依据摘要

本报告迁移时已回读 `/Users/hula/workspace/multiagent-orchestration-system/reports/hermes-project-boundary-and-management-audit.md` 原文，关键原文结论如下，作为本规划的证据底座：

- 审计报告第 1 节指出：项目边界目前由 Git 仓库顶层、Hermes profile 的 `terminal.cwd`、task_guard workspace key、Kanban task 的 `workspace_path` / board / tenant 字段共同隐式表达；尚未发现统一的 Hermes `project_id` / `project_registry` / `project_root` 管理层。
- ASK 的 Git top-level 是 `/Users/hula/workspace`，而业务根是 `/Users/hula/workspace/ASK`；multiagent 的 Git top-level 与 common dir 均在 `/Users/hula/workspace/multiagent-orchestration-system` 内。
- Hermes default 与 ASK profiles 当前 `terminal.cwd` 均指向 ASK；profiles 可表达执行角色与默认工作目录，但不能单独证明项目边界。
- Kanban `tasks` 表包含 `workspace_path`、`tenant`、`dispatch_mode`、`session_id` 等字段；但审计未发现 `project_id` 字段。
- 审计建议短期建立 registry，只读约定先行，逐步接入 Kanban / task_guard / Dashboard / Gateway。

这些原文依据与本报告第 0 节字段化结论一致：现阶段不声称 Hermes 已有严格原生 Project Registry；先使用 Project Overlay Registry 是最低风险路线。

## 12. 写入与验证要求

正式报告写入后必须执行以下只读验证，才能标记完成：

1. 回读本文件头部、字段化结论、Project Overlay Registry、task_guard 三元组、Reporter 项目头、ASK Git root 修复路线。
2. 在 `/Users/hula/workspace/multiagent-orchestration-system` 运行 `git status --short`，确认新增范围可解释。
3. 检查 multiagent 禁止路径 `.gitignore`、`.git`、`package.json`、`pnpm-lock.yaml` 未被本轮触碰。
4. 检查 ASK 禁止路径和源码 dirty 状态只作为既有状态记录，不归因本轮。
5. task_guard / todo 仅在上述回读和 Git 范围验证后标记 completed。

## 13. 人话版 6 点说明

1. **现在缺的不是一个命令，而是一张项目身份证表。** Hermes 当前有 profile、Kanban、task_guard、Gateway 等能力，但它们还没有被一个严格原生 Project Registry 统一约束。
2. **ASK 可以马上登记为项目，但要老实写明它现在还挂在父级 Git 仓库下面。** 也就是业务根是 ASK，Git 根仍是 `/Users/hula/workspace`。
3. **multiagent 项目可以马上登记为独立项目。** 它已经有自己的 `.git`，报告和编排资产放在这里更清楚。
4. **Reporter 必须带项目头。** 飞书里每次汇报都要说明 project_id、业务根、Git 根、task_guard workspace 和目标仓库，避免把 ASK 与 multiagent 混成一个仓库。
5. **ASK Git root 修复不能现在动。** 这涉及 `.git` 边界和既有 dirty，需要冻结窗口、回滚方案和老板审批。
6. **下一步要人工批准后再做。** 可以先批 Project Overlay Registry 草案，再批 task_guard / Reporter 接入，最后单独批 ASK Git root 迁移。

