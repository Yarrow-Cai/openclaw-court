#!/bin/bash
# 差役适配器：pi
# 契约：读 dispatch.json → 执行 → 产物落盘 → 以差役真实退出码退出
set -o pipefail

DISPATCH="${1:?用法: pi.sh <dispatch.json>}"
[ -f "$DISPATCH" ] || { echo "差遣单不存在: $DISPATCH" >&2; exit 2; }

command -v jq >/dev/null || { echo "缺 jq" >&2; exit 3; }
command -v pi >/dev/null || { echo "pi 未安装" >&2; exit 4; }

# 差遣单字段是中文键，jq 必须用 ["键"] 取，不能用 .键
JOB=$(jq -r '.["job_id"]' "$DISPATCH")
TASK=$(jq -r '.["任务"]' "$DISPATCH")
OUT=$(jq -r '.["产物目录"]' "$DISPATCH")
LIMIT=$(jq -r '.["期限"]' "$DISPATCH")
# 验收必须逐条交到差役手上——标准不进提示词，御史按另一份标准驳回就是必然
VERIFY=$(jq -r '.["验收"] // empty | if type=="array" then [to_entries[] | "\(.key+1). \(.value)"] | join("\n") elif type=="string" then . else empty end' "$DISPATCH" 2>/dev/null)

[ "$JOB" != "null" ] && [ -n "$JOB" ] || { echo "差遣单缺 job_id" >&2; exit 5; }
[ "$TASK" != "null" ] && [ -n "$TASK" ] || { echo "差遣单缺 任务" >&2; exit 6; }
[ "$OUT" != "null" ] && [ -n "$OUT" ] || { echo "差遣单缺 产物目录" >&2; exit 7; }
[ -n "$VERIFY" ] && [ "$VERIFY" != "null" ] || { echo "差遣单缺 验收：无验收标准不得开工" >&2; exit 9; }

mkdir -p "$OUT" || { echo "产物目录建不了: $OUT" >&2; exit 8; }

echo "[$(date -Iseconds)] job=$JOB 差役=pi 期限=${LIMIT}" | tee "$OUT/run.txt"
echo "任务: $TASK" | tee -a "$OUT/run.txt"
printf '%s\n' "$VERIFY" > "$OUT/acceptance.txt"
echo "验收:" | tee -a "$OUT/run.txt"
printf '%s\n' "$VERIFY" | tee -a "$OUT/run.txt"

# 验收逐条随任务下发，差役须在产物中逐条落点
PROMPT="$TASK

【验收标准｜必须逐条满足，缺一条即判不合格】
$VERIFY

【交付要求】
- 产物写入 ${OUT}，路径与差遣单一致。
- 上述每一条验收都必须在产物中有对应落点。
- 不得自行更改或忽略验收标准；做不到就明确说明，不要交白卷。"

MODEL="${PI_MODEL:-cpa/auto-pro}"
pi -p --model "$MODEL" "$PROMPT" 2>&1 | tee -a "$OUT/log.txt"
RC=${PIPESTATUS[0]}

echo "[$(date -Iseconds)] model=$MODEL exit=$RC" | tee -a "$OUT/run.txt"
exit "$RC"
