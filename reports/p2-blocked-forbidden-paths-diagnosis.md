# P2 blocked forbidden paths 诊断报告

项目：multiagent-orchestration-system

结论：BLOCKED。P2 验证失败不是 multiagent-orchestration-system 本项目允许范围内文件造成的，而是 `/Users/hula/workspace` 父仓库中 ASK 禁止路径存在既有脏状态，触发 `FORBIDDEN_ASK_PARENT_REPO_PATHS_CLEAN`。

## 诊断来源

- 诊断时间：`2026-06-29T05:18:22+0800`
- 诊断方式：只读 `git status --porcelain=v1 -uall`、`git rev-parse --show-toplevel`、`git check-ignore -v`
- 诊断工作区：`/Users/hula/workspace/multiagent-orchestration-system`
- 既有验证报告：`reports/p2-task-guard-project-registry-report.md`
- 验证脚本：`scripts/validation/verify-task-guard-project-registry.rb`
- 长输出归档：`/Users/hula/.hermes/tool_result_archive/20260628-211515__terminal__4e72716970e2.json`

## Git root 边界

```text
workspace=/Users/hula/workspace
ASK=/Users/hula/workspace
multiagent=/Users/hula/workspace/multiagent-orchestration-system
```

解释：

- ASK 当前仍由父仓库 `/Users/hula/workspace` 管理；因此 ASK 路径状态必须从父仓库视角读取。
- multiagent-orchestration-system 已是独立 Git root：`/Users/hula/workspace/multiagent-orchestration-system`。
- 父仓库已通过 `.gitignore` 忽略 `multiagent-orchestration-system/`：`.gitignore:1:multiagent-orchestration-system/`。

## 失败项分类

### 1. 直接阻塞 P2 的 ASK 父仓库禁止路径状态

检查名：`FORBIDDEN_ASK_PARENT_REPO_PATHS_CLEAN`

父仓库命令范围：

```text
git -C /Users/hula/workspace status --porcelain=v1 -uall -- ASK/.gitignore ASK/package.json ASK/pnpm-lock.yaml ASK/src ASK/tests
```

输出：

```text
 M ASK/.gitignore
M  ASK/src/packages/infrastructure/rate-limit/token-bucket.ts
M  ASK/src/packages/infrastructure/security/input-validator.ts
M  ASK/src/packages/infrastructure/security/xss-filter.ts
D  ASK/tests/unit/phase4-security-helpers.test.ts
D  ASK/tests/unit/phase4-token-bucket.test.ts
```

分类：

| 路径 | 状态 | 分类 | 对 P2 的影响 |
|---|---:|---|---|
| `ASK/.gitignore` | ` M` | ASK 父仓库禁止路径，工作区修改 | 阻塞 |
| `ASK/src/packages/infrastructure/rate-limit/token-bucket.ts` | `M ` | ASK 源码禁止路径，索引修改 | 阻塞 |
| `ASK/src/packages/infrastructure/security/input-validator.ts` | `M ` | ASK 源码禁止路径，索引修改 | 阻塞 |
| `ASK/src/packages/infrastructure/security/xss-filter.ts` | `M ` | ASK 源码禁止路径，索引修改 | 阻塞 |
| `ASK/tests/unit/phase4-security-helpers.test.ts` | `D ` | ASK 测试禁止路径，索引删除 | 阻塞 |
| `ASK/tests/unit/phase4-token-bucket.test.ts` | `D ` | ASK 测试禁止路径，索引删除 | 阻塞 |

补充：从 `/Users/hula/workspace/ASK` 执行等价路径检查，输出与父仓库一致；这是因为 ASK 的 Git root 仍是 `/Users/hula/workspace`，不是 `/Users/hula/workspace/ASK`。

### 2. multiagent 项目禁止路径状态

检查范围：`.gitignore package.json pnpm-lock.yaml src packages ASK`

输出为空。

结论：`FORBIDDEN_MULTIAGENT_PATHS_CLEAN` 当前没有发现脏状态，multiagent 项目禁止路径不是本次 P2 阻塞原因。

### 3. multiagent 本任务允许范围状态

检查范围：`config templates reports scripts/validation`

```text
 M templates/a2a-work-order-protocol.md
?? config/projects.yaml
?? reports/hermes-project-boundary-and-management-audit.md
?? reports/p1-reporter-project-routing-report.md
?? reports/p2-task-guard-project-registry-report.md
?? reports/post-upgrade-project-management-plan.md
?? reports/project-overlay-registry-implementation-report.md
?? reports/p2-blocked-forbidden-paths-diagnosis.md
?? scripts/validation/verify-task-guard-project-registry.rb
?? templates/task-guard-project-registry-gate.md
```

说明：以上属于当前 multiagent 项目的 P0/P1/P2 规划、模板、验证脚本和报告范围；它们不是 `FORBIDDEN_ASK_PARENT_REPO_PATHS_CLEAN` 的失败来源。

## 与既有 P2 报告一致性

既有报告 `reports/p2-task-guard-project-registry-report.md` 的结论为：

- 总检查项：21
- 通过：20
- 失败：1
- 唯一失败项：`FORBIDDEN_ASK_PARENT_REPO_PATHS_CLEAN`
- multiagent 禁止路径状态：干净
- ASK 父仓库禁止路径状态：存在外部脏状态

本次只读复核与既有报告一致。

## 当前完成状态

- 已完成：定位 P2 阻塞根因。
- 已完成：确认 multiagent 独立仓库边界与父仓库忽略规则。
- 已完成：确认 multiagent 禁止路径干净。
- 已完成：确认 ASK 禁止路径存在 6 条阻塞状态。
- 未完成：P2 验证整体通过；原因是 ASK 禁止路径脏状态仍未处理。

## 建议下一步

推荐优先选项：由 ASK 专项任务单独处理或豁免这 6 条 ASK 禁止路径状态，然后重新运行：

```bash
ruby scripts/validation/verify-task-guard-project-registry.rb
```

不建议在 P2 任务内直接清理 ASK 路径，因为这些路径属于 ASK 父仓库禁止范围，且包含源码修改和测试删除，可能是其他阶段或人工工作产物。未经 owner 明确授权，不应执行 `git restore`、`git reset`、删除、移动、提交或 stash。

## 完成标准

P2 可从 BLOCKED 转为完成，需要满足至少一种条件：

1. ASK 禁止路径状态被合法处理后，`FORBIDDEN_ASK_PARENT_REPO_PATHS_CLEAN` 通过；或
2. owner 明确批准将当前 ASK 禁止路径状态作为 P2 豁免，并把豁免原因、范围和责任任务写入报告/ledger。
