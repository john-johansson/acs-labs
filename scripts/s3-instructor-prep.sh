#!/usr/bin/env bash
# Session 3 instructor prep (NOT for students).
# Run once on the bastion before students start Session 3.
# Frees ocp4-cis / ocp4-cis-node from the demo acs-catch-all schedule so
# Exercise 1 (CLI) and Exercise 2 (RHACS UI Create) can own those profiles.
# Idempotent: safe to re-run.

set -euo pipefail

CIS_PROFILES=(ocp4-cis ocp4-cis-node)
LAB_BINDINGS=(cis-weekly-scan cis-audit-schedule)

echo "=== Session 3 instructor prep ==="

if [[ -z "${ROX_CENTRAL_ADDRESS:-}" || -z "${ROX_API_TOKEN:-}" ]]; then
  echo "ERROR: ROX_CENTRAL_ADDRESS and ROX_API_TOKEN must be set on the bastion." >&2
  exit 1
fi

ROX_ENDPOINT="${ROX_ENDPOINT:-$ROX_CENTRAL_ADDRESS}"
AUTH_HEADER=( -H "Authorization: Bearer ${ROX_API_TOKEN}" )
JSON_HEADER=( -H "Content-Type: application/json" )

echo "Removing leftover lab ScanSettingBindings (if any)..."
for name in "${LAB_BINDINGS[@]}"; do
  oc delete scansettingbinding "${name}" -n openshift-compliance --ignore-not-found
done

echo "Locating RHACS scan configuration acs-catch-all..."
CFG_JSON="$(curl -sk "${AUTH_HEADER[@]}" \
  "${ROX_CENTRAL_ADDRESS}/v2/compliance/scan/configurations")"

CFG_ID="$(python3 -c '
import json,sys
d=json.load(sys.stdin)
matches=[c for c in d.get("configurations",[]) if c.get("scanName")=="acs-catch-all"]
if not matches:
  sys.exit("acs-catch-all scan configuration not found in RHACS")
print(matches[0]["id"])
' <<<"${CFG_JSON}")"

DETAIL_JSON="$(curl -sk "${AUTH_HEADER[@]}" \
  "${ROX_CENTRAL_ADDRESS}/v2/compliance/scan/configurations/${CFG_ID}")"

PUT_JSON="$(python3 -c '
import json,sys
cis=set(sys.argv[1:])
d=json.load(sys.stdin)
profiles=[p for p in d["scanConfig"]["profiles"] if p not in cis]
cluster_ids=[c["clusterId"] for c in d.get("clusterStatus",[]) if c.get("clusterId")]
if not cluster_ids:
  sys.exit("acs-catch-all has no cluster IDs; cannot update scan configuration")
payload={
  "id": d["id"],
  "scanName": d["scanName"],
  "clusters": cluster_ids,
  "scanConfig": {
    "oneTimeScan": d["scanConfig"].get("oneTimeScan", False),
    "profiles": profiles,
    "scanSchedule": d["scanConfig"].get("scanSchedule", {}),
    "description": d["scanConfig"].get("description", ""),
    "notifiers": d["scanConfig"].get("notifiers", []),
  },
}
print(json.dumps(payload))
removed=sorted(cis & set(d["scanConfig"]["profiles"]))
print("profiles_before="+",".join(d["scanConfig"]["profiles"]), file=sys.stderr)
print("profiles_after="+",".join(profiles), file=sys.stderr)
print("removed="+(",".join(removed) if removed else "(none)"), file=sys.stderr)
' "${CIS_PROFILES[@]}" <<<"${DETAIL_JSON}")"

echo "Updating acs-catch-all in RHACS to drop CIS profiles..."
HTTP_CODE="$(curl -sk -o /tmp/s3-instructor-prep-put.out -w "%{http_code}" \
  -X PUT "${AUTH_HEADER[@]}" "${JSON_HEADER[@]}" \
  --data "${PUT_JSON}" \
  "${ROX_CENTRAL_ADDRESS}/v2/compliance/scan/configurations/${CFG_ID}")"

if [[ "${HTTP_CODE}" != "200" ]]; then
  echo "ERROR: RHACS PUT failed (HTTP ${HTTP_CODE}): $(cat /tmp/s3-instructor-prep-put.out)" >&2
  exit 1
fi

echo "Waiting for cluster ScanSettingBinding to drop CIS profiles..."
for _ in $(seq 1 30); do
  BIND_PROFILES="$(oc get scansettingbinding acs-catch-all -n openshift-compliance \
    -o jsonpath='{range .profiles[*]}{.name}{"\n"}{end}' 2>/dev/null || true)"
  STILL_CIS=0
  for p in "${CIS_PROFILES[@]}"; do
    if grep -qx "${p}" <<<"${BIND_PROFILES}"; then
      STILL_CIS=1
      break
    fi
  done
  if [[ "${STILL_CIS}" -eq 0 ]]; then
    break
  fi
  sleep 2
done

BIND_PROFILES="$(oc get scansettingbinding acs-catch-all -n openshift-compliance \
  -o jsonpath='{range .profiles[*]}{.name}{"\n"}{end}' 2>/dev/null || true)"

# Fallback: patch the CR if RHACS sync is slow or stuck
NEED_PATCH=0
for p in "${CIS_PROFILES[@]}"; do
  if grep -qx "${p}" <<<"${BIND_PROFILES}"; then
    NEED_PATCH=1
    break
  fi
done

if [[ "${NEED_PATCH}" -eq 1 ]]; then
  echo "RHACS sync still lists CIS on the cluster binding; patching ScanSettingBinding as fallback..."
  oc get scansettingbinding acs-catch-all -n openshift-compliance -o json \
    | python3 -c '
import json,sys
cis={"ocp4-cis","ocp4-cis-node"}
d=json.load(sys.stdin)
d["profiles"]=[p for p in d.get("profiles",[]) if p.get("name") not in cis]
json.dump(d, sys.stdout)
' | oc apply -f -
fi

echo ""
echo "=== Ready checklist ==="
echo "RHACS acs-catch-all profiles (should omit ocp4-cis / ocp4-cis-node):"
curl -sk "${AUTH_HEADER[@]}" \
  "${ROX_CENTRAL_ADDRESS}/v2/compliance/scan/configurations/${CFG_ID}" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(" ", ", ".join(d["scanConfig"]["profiles"]))'

echo "Cluster ScanSettingBinding acs-catch-all profiles:"
oc get scansettingbinding acs-catch-all -n openshift-compliance \
  -o jsonpath='{range .profiles[*]}{"  "}{.name}{"\n"}{end}'

echo ""
echo "CIS profiles are free for Session 3."
echo "Coverage still has non-CIS results from acs-catch-all."
echo "Students may start Exercise 1."
echo "=== Session 3 instructor prep complete ==="
