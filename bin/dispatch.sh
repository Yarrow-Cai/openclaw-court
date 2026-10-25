#!/bin/bash
# 派差总闸：太子只能调这一条，不许自己"想起来"
# 用法: dispatch.sh <JOB-YYYYMMDD-NNN>
# 退出码: 0 全链通过（以御史裁定为准）｜10 案卷不合规｜11 差遣单不合规
#         12 回执不合规｜13 差役执行失败｜14 唤起 agent 失败｜15 御史驳回
set -o pipefail

JOB_ID="${1:?用法: dispatch.sh <JOB-YYYYMMDD-NNN>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JOB_DIR="$ROOT/jobs/$JOB_ID"
JOB_JSON="$JOB_DIR/job.json"
DISPATCH="$JOB_DIR/dispatch.json"
RECEIPT="$JOB_DIR/receipt.json"
ART_DIR="$ROOT/artifacts/$JOB_ID"
RUNLOG="$JOB_DIR/dispatch-run.log"

command -v jq >/dev/null || { echo "缺 jq" >&2; exit 2; }
command -v openclaw >/dev/null || { echo "缺 openclaw" >&2; exit 2; }

log() { echo "[$(date -Iseconds)] $*" | tee -a "$RUNLOG"; }
die() { local c=$1; shift; log "✗ $*"; echo "$*" >&2; exit "$c"; }

# 带超时执行，超时即判失败
run_to() { # run_to <秒> <命令...>
  local t=$1; shift
  "$@" & local pid=$!
  ( sleep "$t"; kill -TERM "$pid" 2>/dev/null ) >/dev/null 2>&1 & local watcher=$!
  wait "$pid"; local rc=$?
  kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
  return "$rc"
}

echo "=== 派差开始 $JOB_ID ===" | tee "$RUNLOG"

# ── ① 案卷六要素 ─────────────────────────────
[ -f "$JOB_JSON" ] || die 10 "案卷不存在: $JOB_JSON"
for k in job_id 旨意 下旨时间 请求人 状态; do
  v=$(jq -r --arg k "$k" '.[$k] // empty' "$JOB_JSON")
  [ -n "$v" ] || die 10 "job.json 缺字段: $k"
done
[ "$(jq -r .job_id "$JOB_JSON")" = "$JOB_ID" ] || die 10 "job_id 与目录名不符"
log "① 案卷合规：$(jq -r '.["旨意"]' "$JOB_JSON" | head -c 60)…"

# 已签结的案子不许重跑
st=$(jq -r '.["状态"]' "$JOB_JSON")
[ "$st" = "已签结" ] && die 10 "案卷已签结，如需重办请另立案"

jq --arg s "已派差" '.["状态"]=$s' "$JOB_JSON" > "$JOB_JSON.tmp" && mv "$JOB_JSON.tmp" "$JOB_JSON"

# ── ② 丞相拆旨出单 ───────────────────────────
rm -f "$DISPATCH"
log "② 唤起丞相拆旨…"
CX_MSG="案卷 $JOB_ID 已在 jobs/$JOB_ID/job.json，旨意为：$(jq -r '.["旨意"]' "$JOB_JSON")。
请依《丞相守则》拆旨，写出 jobs/$JOB_ID/dispatch.json，字段须齐：job_id、差役、任务、验收、期限、产物目录。
差役目前只能填 pi；产物目录必须是 artifacts/$JOB_ID/；验收须可机器判定。
你只写文书，不得执行任务。写完只回一句：已出单。"
if ! run_to 600 openclaw agent --agent chengxiang -m "$CX_MSG" >> "$RUNLOG" 2>&1; then
  die 14 "丞相未正常应答"
fi

# ── ③ 差遣单六字段 ───────────────────────────
[ -f "$DISPATCH" ] || die 11 "丞相未出单：jobs/$JOB_ID/dispatch.json 不存在"
for k in job_id 差役 任务 验收 期限 产物目录; do
  v=$(jq -r --arg k "$k" '.[$k] // empty | if type=="array" then (if length>0 then "ok" else "" end) else tostring end' "$DISPATCH")
  [ -n "$v" ] || die 11 "dispatch.json 缺字段: $k"
done
DJ=$(jq -r .job_id "$DISPATCH");  [ "$DJ" = "$JOB_ID" ] || die 11 "差遣单 job_id 不符: $DJ"
AD="$(jq -r '.["差役"]' "$DISPATCH")"
OUTDIR="$(jq -r '.["产物目录"]' "$DISPATCH")"
[ "$OUTDIR" = "artifacts/$JOB_ID/" ] || die 11 "产物目录不合规: $OUTDIR"
ADAPTER="$ROOT/adapters/$AD.sh"
[ -x "$ADAPTER" ] || die 11 "无此差役适配器: $AD"
log "③ 差遣单合规：差役=$AD 期限=$(jq -r '.["期限"]' "$DISPATCH")"

jq --arg s "执行中" '.["状态"]=$s' "$JOB_JSON" > "$JOB_JSON.tmp" && mv "$JOB_JSON.tmp" "$JOB_JSON"

# ── ④ 差役执行 ───────────────────────────────
mkdir -p "$ART_DIR" || die 13 "产物目录建不了: $ART_DIR"
log "④ 差役开工…"
( cd "$ROOT" && "$ADAPTER" "$DISPATCH" ) >> "$RUNLOG" 2>&1
RC=$?
echo "$RC" > "$JOB_DIR/exit_code"
log "④ 差役退出码=$RC"
[ "$RC" -eq 0 ] || log "④ 差役非零退出，交御史裁定"

jq --arg s "待签结" '.["状态"]=$s' "$JOB_JSON" > "$JOB_JSON.tmp" && mv "$JOB_JSON.tmp" "$JOB_JSON"

# ── ⑤ 御史核验 ───────────────────────────────
rm -f "$RECEIPT"
log "⑤ 唤起御史核验…"
YS_MSG="案卷 $JOB_ID：差遣单 jobs/$JOB_ID/dispatch.json，差役产物在 artifacts/$JOB_ID/，差役退出码 $RC。
请依《御史守则》独立核验：对照 dispatch.json 的『验收』逐条实跑复核（不许只看差役自述），然后写 jobs/$JOB_ID/receipt.json，字段：job_id、执行者、exit_code、产物、摘要、裁定、驳回理由、签署时间。
裁定只能是 准结 或 驳回。你只核验，不得改动产物、不得替差役补做。写完只回一句：已签结。"
if ! run_to 900 openclaw agent --agent yushidafu -m "$YS_MSG" >> "$RUNLOG" 2>&1; then
  die 14 "御史未正常应答"
fi

# ── ⑥ 回执合规 ───────────────────────────────
[ -f "$RECEIPT" ] || die 12 "御史未签结：jobs/$JOB_ID/receipt.json 不存在"
VERDICT="$(jq -r '.["裁定"]' "$RECEIPT")"
case "$VERDICT" in
  准结) jq --arg s "已签结" '.["状态"]=$s' "$JOB_JSON" > "$JOB_JSON.tmp" && mv "$JOB_JSON.tmp" "$JOB_JSON" ;;
  驳回) jq --arg s "已驳回" '.["状态"]=$s' "$JOB_JSON" > "$JOB_JSON.tmp" && mv "$JOB_JSON.tmp" "$JOB_JSON" ;;
  *) die 12 "裁定非法: $VERDICT" ;;
esac

# ── ⑦ 一句话交差 ─────────────────────────────
echo "──────────────────────────────"
echo "job_id   : $JOB_ID"
echo "差役     : $AD (exit=$RC)"
echo "差遣单   : jobs/$JOB_ID/dispatch.json"
echo "产物     : artifacts/$JOB_ID/"
echo "回执     : jobs/$JOB_ID/receipt.json"
echo "裁定     : $VERDICT"
echo "摘要     : $(jq -r '.["摘要"]' "$RECEIPT")"
echo "──────────────────────────────"

[ "$VERDICT" = "准结" ] || exit 15
exit 0
