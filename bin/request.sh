#!/bin/bash
# 太子专用：交派差房（不直接唤起 agent，避开 agent-exec 归属限制）
# 用法: request.sh <JOB-YYYYMMDD-NNN>
set -euo pipefail
JOB_ID="${1:?用法: request.sh <JOB-YYYYMMDD-NNN>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JOB_DIR="$ROOT/jobs/$JOB_ID"

[ -f "$JOB_DIR/job.json" ] || { echo "案卷不存在: $JOB_DIR/job.json" >&2; exit 10; }
command -v jq >/dev/null || { echo "缺 jq" >&2; exit 2; }

if [ "$(jq -r '.["状态"]' "$JOB_DIR/job.json")" = "已签结" ]; then
  echo "案卷已签结，如需重办请另立案" >&2
  exit 11
fi

date -Iseconds > "$JOB_DIR/requested"
echo "已交派差房：$JOB_ID"
echo "派差房每 30 秒巡查一次；办完会写 receipt.json，届时凭裁定回奏。"
