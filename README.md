# 朝堂 · Court

一套**可审计、可追责**的多角色协作编排层，只作用于 OpenClaw。
干活的全在朝堂之外（外部 Agent CLI），朝堂只负责**想清楚**与**验明白**。

> 设计取舍：取秦制之简（三公、无中间层、监察独立），弃三省六部之繁（四道手、无人签字）。
> 三省六部的名号保留作对照，见 `docs/04-秦制对照.md`。

---

## 一、角色（只此四人，不多设）

| 角色 | 唯一职责 | 绝不做 |
|---|---|---|
| **太子** `taizi` | 接旨、立文书、回奏 | 不拆旨、不派差、不碰产物 |
| **丞相** `chengxiang` | 拆旨、出差遣单、汇总 | 不亲自执行、不自己验活 |
| **御史大夫** `yushidafu` | 登记、核验、签结 | 不改产物、不替人补漏 |
| **差役池** | 外部 Agent 干活 | 不进朝堂，只交回执 |

差役池当前只启用 **pi**；codex / claude / kimi 暂不安装，适配器预留。

---

## 二、一条旨意的走法

```
① 大王下旨（飞书）
        ↓
② 太子：立 job.json（编号、落盘）
        ↓
③ 丞相：读 job.json → 出 dispatch.json，点名差役
        ↓
④ 差役：外部 Agent 执行 → 产物落 artifacts/<job-id>/
        ↓
⑤ 御史大夫：验退出码 + 产物 + 摘要 → 签 receipt.json
        ↓
⑥ 太子：持签结回奏大王
```

③ 至 ⑤ 之间太子不插手；② 至 ⑥ 之间丞相不越权。每步只认上一步的文书。

---

## 三、三条铁律

1. **无文书不办** — 没有 `job.json` 的旨意，丞相不接。
2. **无签结不奏** — 没有 `receipt.json` 的任务，太子不得回奏「已成」。
3. **同人不同验** — 丞相派的活，丞相不得签结。

---

## 四、目录

```
court/
├── bin/              派差总闸 dispatch.sh / 交派房 request.sh / 巡查 watch.sh
├── roles/            三份 SOUL.md（各角色的人格与硬规则）
├── schemas/          job / dispatch / receipt 三份 JSON Schema
├── adapters/         差役适配层（pi.sh …）
├── docs/             角色、分工、工作流、制度对照
├── examples/         一个完整案例（JOB-20261024-001，已签结）
├── jobs/             运行时：每旨一目录（不入库）
└── artifacts/        运行时：差役产物（不入库）
```

`jobs/` 与 `artifacts/` 为运行时数据，不入库（见 `.gitignore`）。

---

## 五、快速开始

```bash
# 1. 立一旨
mkdir -p jobs/JOB-$(date +%Y%m%d)-001

# 2. 太子立文书 → 丞相出差遣单 → 差役执行
bash adapters/pi.sh jobs/JOB-xxx/dispatch.json

# 3. 御史签结
#    检查 artifacts/<job-id>/ 与 receipt.json 是否齐备
```

---

## 六、状态机

```
已立案 → 已派差 → 执行中 → 待签结 → 已签结
                    ↘ 已驳回 ↗
                    ↘ 已超时
```

任何状态都可由**御史大夫**置为 `已驳回` 或 `已超时`，太子据此回奏。

---

## 七、依赖

| 依赖 | 用途 | 必需 |
|---|---|---|
| `bash` + `jq` | 派差脚本解析中文键文书 | 是 |
| [OpenClaw](https://docs.openclaw.ai) CLI | 唤起丞相 / 御史 agent | 是 |
| `pi`（或自写适配器） | 差役执行 | 是 |
| `lark-cli` + 飞书 app | 把回执推回飞书（`COURT_REPORT_UNION_ID`） | 否 |

差役适配器契约：读 `dispatch.json` → 执行 → 产物落 `产物目录` → 以真实退出码退出。
**验收标准会随任务逐条下发**，缺 `验收` 的差遣单直接拒跑（`exit 9`）。

## 八、许可

MIT，见 [LICENSE](LICENSE)。
