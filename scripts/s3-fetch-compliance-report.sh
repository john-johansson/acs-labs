#!/usr/bin/env bash
# Fetch the cis-audit-schedule compliance report from Central and summarize the CSV.
# Uses ROX_CENTRAL_ADDRESS and ROX_API_TOKEN already set on the bastion.
# Idempotent: safe to run again (requests a new download job each time).

set -euo pipefail

if [[ -z "${ROX_CENTRAL_ADDRESS:-}" || -z "${ROX_API_TOKEN:-}" ]]; then
  echo "ERROR: ROX_CENTRAL_ADDRESS and ROX_API_TOKEN must be set on the bastion." >&2
  exit 1
fi

AUTH_H="Authorization: Bearer ${ROX_API_TOKEN}"
JSON_H="Content-Type: application/json"
BASE="${ROX_CENTRAL_ADDRESS}"
ZIP="${HOME}/compliance-report.zip"
OUT_DIR="${HOME}/compliance-report"

echo "Looking up cis-audit-schedule..."
CFG_JSON="$(curl -sk -H "${AUTH_H}" "${BASE}/v2/compliance/scan/configurations")"
CFG_ID="$(python3 -c '
import json,sys
d=json.load(sys.stdin)
matches=[c for c in d.get("configurations",[]) if c.get("scanName")=="cis-audit-schedule"]
if not matches:
  sys.exit("cis-audit-schedule was not found in RHACS. Create it in Exercise 2 first.")
print(matches[0]["id"])
' <<<"${CFG_JSON}")"
echo "CFG_ID=${CFG_ID}"

echo "Requesting an on-demand DOWNLOAD report..."
RUN_JSON="$(curl -sk -H "${AUTH_H}" -H "${JSON_H}" -X POST \
  --data "{\"scanConfigId\":\"${CFG_ID}\",\"reportNotificationMethod\":\"DOWNLOAD\"}" \
  "${BASE}/v2/compliance/scan/configurations/reports/run")"
echo "${RUN_JSON}"
SUBMITTED_AT="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("submittedAt") or "")' <<<"${RUN_JSON}")"
if [[ -z "${SUBMITTED_AT}" ]]; then
  echo "ERROR: report request did not return submittedAt." >&2
  exit 1
fi

JOB_ID=""
STATE=""
for i in $(seq 1 24); do
  HIST="$(curl -sk -H "${AUTH_H}" \
    "${BASE}/v2/compliance/scan/configurations/${CFG_ID}/reports/my-history?reportParamQuery.pagination.limit=10")"
  PARSED="$(python3 -c '
import json,sys
from datetime import datetime, timedelta
submitted = sys.argv[1]
d = json.load(sys.stdin)
def parse(ts):
    return datetime.fromisoformat(ts.replace("Z", "+00:00"))
cutoff = parse(submitted) - timedelta(seconds=5)
snaps = d.get("complianceReportSnapshots") or []
for s in snaps:
    st = s.get("reportStatus") or {}
    started = st.get("startedAt") or ""
    if not started:
        continue
    if parse(started) < cutoff:
        continue
    print((s.get("reportJobId") or "") + "|" + (st.get("runState") or ""))
    break
else:
    print("|")
' "${SUBMITTED_AT}" <<<"${HIST}")"
  JOB_ID="${PARSED%%|*}"
  STATE="${PARSED#*|}"
  echo "poll ${i}: job=${JOB_ID:-pending} state=${STATE:-waiting}"
  if [[ "${STATE}" == "GENERATED" || "${STATE}" == "DELIVERED" ]]; then
    break
  fi
  if [[ "${STATE}" == "FAILURE" ]]; then
    echo "ERROR: report job failed." >&2
    exit 1
  fi
  sleep 5
done

if [[ -z "${JOB_ID}" || ( "${STATE}" != "GENERATED" && "${STATE}" != "DELIVERED" ) ]]; then
  echo "ERROR: report was not ready in time (last state: ${STATE:-unknown})." >&2
  exit 1
fi

echo "Downloading ${ZIP}..."
curl -sk -H "${AUTH_H}" -o "${ZIP}" \
  "${BASE}/v2/compliance/scan/configurations/reports/download?id=${JOB_ID}"
unzip -l "${ZIP}"
rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"
unzip -o "${ZIP}" -d "${OUT_DIR}"

CSV="$(find "${OUT_DIR}" -name '*.csv' | head -1)"
if [[ -z "${CSV}" ]]; then
  echo "ERROR: ZIP did not contain a CSV." >&2
  exit 1
fi
echo "CSV=${CSV}"
echo

python3 - "${CSV}" <<'PY'
import csv
import sys
from collections import Counter

path = sys.argv[1]
with open(path, newline="", encoding="utf-8", errors="replace") as f:
    rows = list(csv.DictReader(f))
if not rows:
    sys.exit("CSV has no data rows")
print("columns:", list(rows[0].keys()))
print("rows:", len(rows))
print("Status counts:", dict(Counter(r.get("Status") for r in rows)))
print("Fail rows:", sum(1 for r in rows if r.get("Status") == "FAIL"))
for status in ("FAIL", "INCONSISTENT"):
    hits = [r for r in rows if r.get("Status") == status][:3]
    for r in hits:
        print(f"{status}: {r.get('Check(CCR)')} | {r.get('Profile(version)')}")
PY
