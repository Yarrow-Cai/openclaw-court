# 差役适配器

每个适配器是一层薄壳，只做四件事：

1. 读 `dispatch.json`（`job_id` / `任务` / `产物目录` / `期限`）
2. 调对应的外部 CLI，把 stdout+stderr 全写进 `artifacts/<job-id>/log.txt`
3. 产物落在 `artifacts/<job-id>/`
4. **以差役真实退出码退出**

## 契约（三条不许破）

- 不修改 `dispatch.json`
- 不写 `receipt.json`（那是御史的笔）
- 不吞退出码（`exit $?` 必须真实）

## 现有

| 适配器 | 状态 |
|---|---|
| `pi.sh` | ✅ 已写（`pi -p "<任务>"`，参数待首次实跑校准） |
| `codex.sh` | 未建（codex 暂不安装） |
| `claude.sh` | 未建（claude 暂不安装） |
| `kimi.sh` | 未建（kimi 暂不安装） |

## 新增一个差役

```bash
cp pi.sh <名字>.sh
# 改调用命令那一行即可，其余契约不变
chmod +x <名字>.sh
```

## 注意

- macOS 默认无 `timeout` 命令；超时控制需另配（`gtimeout` 或 perl 实现）。
  `pi.sh` 当前把期限写进日志，尚未强制中断，首次实跑后再定。
- 差役若需要工作目录，统一用 `--working-dir artifacts/<job-id>`（各 CLI 参数不同，需逐个核）。
