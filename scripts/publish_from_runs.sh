#!/usr/bin/env bash
set -euo pipefail
JOB_ID="${1:-}"
[[ -z "$JOB_ID" ]] && { echo "Usage: $0 <cron_job_id>"; exit 2; }
cd "$HOME/.openclaw/workspace/agent-site"
raw="$(openclaw cron runs --id "$JOB_ID" --limit 1 --expect-final --timeout 180000 2>&1 || true)"
summary="$(printf "%s\n" "$raw" | tr -d '\r' | awk -F'"summary": "' 'NF>1{print $2; exit}' | awk -F'","runAtMs"' '{print $1}')"
[[ -z "$summary" ]] && { printf "%s\n" "$raw" > scripts/last_runs_pull.log; echo "No summary found"; exit 1; }
summary_txt="$(python3 - <<'PY'
import sys
s=sys.stdin.read()
s=s.replace('\\\\n','\n').replace('\\\\t','\t').replace('\\\\r','\r').replace('\\\\\\"','"')
print(s, end="")
PY
<<<"$summary")"
md="$(printf "%s\n" "$summary_txt" | awk 'f{print} /@@SITE_MD_BEGIN/{f=1;next} /@@SITE_MD_END/{f=0}')"
js="$(printf "%s\n" "$summary_txt" | awk 'f{print} /@@SITE_JSON_BEGIN/{f=1;next} /@@SITE_JSON_END/{f=0}')"
[[ -z "${md// }" || -z "${js// }" ]] && { printf "%s\n" "$summary_txt" > scripts/last_summary.txt; echo "No SITE blocks"; exit 1; }
date_str="$(printf "%s\n" "$js" | sed -n 's/.*"date"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
[[ -z "$date_str" ]] && date_str="$(date +%F)"
mkdir -p feeds digests
printf "%s\n" "$md" > "digests/${date_str}.md"
printf "%s\n" "$md" > "feeds/latest.md"
printf "%s\n" "$js" > "feeds/latest.json"
git add "digests/${date_str}.md" "feeds/latest.md" "feeds/latest.json"
if git diff --cached --quiet; then echo "No changes"; exit 0; fi
git commit -m "publish digest ${date_str}"
git push
echo "Published ${date_str}"
