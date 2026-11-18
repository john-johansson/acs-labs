#!/usr/bin/env bash
# Session 3 instructor prep (NOT for students).
# Run once on the bastion before students start Session 3.
# Deletes the demo acs-catch-all schedule and its ScanSettingBinding so
# Exercise 1 (CLI) and Exercise 2 (RHACS UI Create) can own the CIS profiles.
# Also removes leftover lab bindings from a previous run.
# Idempotent: safe to re-run.

set -euo pipefail

DEMO_SCHEDULE=acs-catch-all
LAB_BINDINGS=(cis-weekly-scan cis-audit-schedule)

echo "=== Session 3 instructor prep ==="

if [[ -z "${ROX_CENTRAL_ADDRESS:-}" || -z "${ROX_API_TOKEN:-}" ]]; then
  echo "ERROR: ROX_CENTRAL_ADDRESS and ROX_API_TOKEN must be set on the bastion." >&2
  exit 1
fi

AUTH_HEADER=( -H "Authorization: Bearer ${ROX_API_TOKEN}" )

echo "Removing leftover lab ScanSettingBindings (if any)..."
for name in "${LAB_BINDINGS[@]}"; do
  oc delete scansettingbinding "${name}" -n openshift-compliance --ignore-not-found
done

echo "Removing demo RHACS scan schedule ${DEMO_SCHEDULE} (if present)..."
CFG_JSON="$(curl -sk "${AUTH_HEADER[@]}" \
  "${ROX_CENTRAL_ADDRESS}/v2/compliance/scan/configurations")"

CFG_ID="$(python3 -c '
import json,sys
name=sys.argv[1]
d=json.load(sys.stdin)
matches=[c for c in d.get("configurations",[]) if c.get("scanName")==name]
print(matches[0]["id"] if matches else "")
' "${DEMO_SCHEDULE}" <<<"${CFG_JSON}")"

if [[ -z "${CFG_ID}" ]]; then
  echo "  ${DEMO_SCHEDULE}: not found in RHACS (ok)"
else
  HTTP_CODE="$(curl -sk -o /tmp/s3-instructor-prep-delete.out -w "%{http_code}" \
    -X DELETE "${AUTH_HEADER[@]}" \
    "${ROX_CENTRAL_ADDRESS}/v2/compliance/scan/configurations/${CFG_ID}")"
  if [[ "${HTTP_CODE}" == "200" || "${HTTP_CODE}" == "204" ]]; then
    echo "  ${DEMO_SCHEDULE}: deleted from RHACS (${CFG_ID})"
  else
    echo "ERROR: RHACS DELETE ${DEMO_SCHEDULE} failed (HTTP ${HTTP_CODE}): $(cat /tmp/s3-instructor-prep-delete.out)" >&2
    exit 1
  fi
fi

echo "Removing cluster ScanSettingBinding ${DEMO_SCHEDULE} (if present)..."
oc delete scansettingbinding "${DEMO_SCHEDULE}" -n openshift-compliance --ignore-not-found

echo "Waiting for ${DEMO_SCHEDULE} to disappear from the cluster..."
for _ in $(seq 1 30); do
  if ! oc get scansettingbinding "${DEMO_SCHEDULE}" -n openshift-compliance >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if oc get scansettingbinding "${DEMO_SCHEDULE}" -n openshift-compliance >/dev/null 2>&1; then
  echo "ERROR: ScanSettingBinding ${DEMO_SCHEDULE} is still present." >&2
  exit 1
fi

echo ""
echo "=== Ready checklist ==="
echo "RHACS scan schedules:"
curl -sk "${AUTH_HEADER[@]}" \
  "${ROX_CENTRAL_ADDRESS}/v2/compliance/scan/configurations" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); names=[c.get("scanName") for c in d.get("configurations",[])]; print(" ", ", ".join(names) if names else "(none)")'

echo "Cluster ScanSettingBindings:"
oc get scansettingbinding -n openshift-compliance 2>/dev/null \
  || echo "  (none)"

echo ""
echo "${DEMO_SCHEDULE} is removed. CIS profiles are free for Session 3."
echo "Students may start Exercise 1."
echo "=== Session 3 instructor prep complete ==="
