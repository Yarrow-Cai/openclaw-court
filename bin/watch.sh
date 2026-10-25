#!/bin/bash
# 派差房：巡查 jobs/*/requested，串行跑 dispatch.sh，办完替太子把回执送到飞书
# 由 Hermes cron（court_dispatcher.sh，每 60 秒）唤起；也可手动跑一次。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$ROOT/var/dispatcher.log"
# 可选：把回执推回飞书（需自行装 lark-cli 并配置应用凭证）
UNION_ID="${COURT_REPORT_UNION_ID:-}"
mkdir -p "$ROOT/var"
trap '' HUP

log() { echo "[$(date -Iseconds)] $*" >> "$LOG"; }

# 以飞书 bot 身份回奏：收件人按 app 隔离，故用 union_id；未配置则静默跳过
report() {
  local job_id="$1" verdict="$2" summary="$3" ad="$4" rc="$5"
  local text body
  if [ -z "$UNION_ID" ] || ! command -v lark-cli >/dev/null; then
    log "未配置飞书回奏（COURT_REPORT_UNION_ID / lark-cli），跳过 $job_id"
    return 0
  fi
  text="【回奏】${job_id}　裁定：${verdict}
差役：${ad}（exit=${rc}）
摘要：${summary}
案卷：${ROOT}/jobs/${job_id}/"
  body=$(jq -n --arg t "$text" --arg rid "$UNION_ID" \
    '{receive_id:$rid, msg_type:"text", content:({text:$t}|tojson)}')
  if printf '%s' "$body" | env -u HERMES_HOME -u _HERMES_GATEWAY OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME}" \
      lark-cli api POST /open-apis/im/v1/messages \
      --params '{"receive_id_type":"union_id"}' \
      --data - > "$ROOT/var/.report.out" 2>&1; then
    log "回奏已送达 $job_id ($(jq -r '.ok // false' "$ROOT/var/.report.out" 2>/dev/null))"
  else
    log "回奏发送失败 $job_id"
  fi
  rm -f "$ROOT/var/.report.json"
}

# 手动补发某个已签结案卷的回奏：watch.sh --report JOB-...
if [ "${1:-}" = "--report" ]; then
  RID="${2:?用法: watch.sh --report <JOB-...>}"
  RJD="$ROOT/jobs/$RID"
  [ -f "$RJD/receipt.json" ] || { echo "该案无回执" >&2; exit 12; }
  report "$RID" \
    "$(jq -r '.["裁定"]' "$RJD/receipt.json")" \
    "$(jq -r '.["摘要"]' "$RJD/receipt.json")" \
    "$(jq -r '.["执行者"]' "$RJD/receipt.json")" \
    "$(jq -r '.["exit_code"]' "$RJD/receipt.json")"
  tail -1 "$LOG"
  exit 0
fi

for req in "$ROOT"/jobs/*/requested; do
  [ -f "$req" ] || continue
  JOB_DIR="$(dirname "$req")"
  JOB_ID="$(basename "$JOB_DIR")"

  [ -f "$JOB_DIR/receipt.json" ] && continue
  [ -f "$JOB_DIR/running" ] && continue
  [ "$(jq -r '.["状态"]' "$JOB_DIR/job.json" 2>/dev/null)" = "已签结" ] && continue

  : > "$JOB_DIR/running"
  log "接手 $JOB_ID"
  bash "$ROOT/bin/dispatch.sh" "$JOB_ID" >> "$ROOT/var/$JOB_ID.out" 2>&1
  RC=$?
  log "完结 $JOB_ID 退出码=$RC"
  rm -f "$JOB_DIR/running"
  mv "$req" "$JOB_DIR/requested.done" 2>/dev/null || true

  if [ -f "$JOB_DIR/receipt.json" ]; then
    report "$JOB_ID" \
      "$(jq -r '.["裁定"]' "$JOB_DIR/receipt.json")" \
      "$(jq -r '.["摘要"]' "$JOB_DIR/receipt.json")" \
      "$(jq -r '.["执行者"]' "$JOB_DIR/receipt.json")" \
      "$(jq -r '.["exit_code"]' "$JOB_DIR/receipt.json")"
  fi
done
