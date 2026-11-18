#!/usr/bin/env bash
# Session 3: Compliance & Network Observability cleanup
# Removes lab-created RHACS schedules, cluster ScanSettingBindings, and
# generated NetworkPolicies so the environment matches a post-instructor-prep
# starting state. Idempotent: safe to run multiple times.
#
# Does not restore CIS profiles into acs-catch-all (instructor prep owns that).

set -euo pipefail

LAB_RHACS_SCHEDULES=(cis-weekly-scan cis-audit-schedule)
LAB_BINDINGS=(cis-weekly-scan cis-audit-schedule)

echo "=== Session 3 cleanup ==="

if [[ -z "${ROX_CENTRAL_ADDRESS:-}" || -z "${ROX_API_TOKEN:-}" ]]; then
  echo "ERROR: ROX_CENTRAL_ADDRESS and ROX_API_TOKEN must be set on the bastion." >&2
  exit 1
fi

AUTH_HEADER=( -H "Authorization: Bearer ${ROX_API_TOKEN}" )

echo "Removing lab RHACS scan schedules (if present)..."
CFG_JSON="$(curl -sk "${AUTH_HEADER[@]}" \
  "${ROX_CENTRAL_ADDRESS}/v2/compliance/scan/configurations")"

for name in "${LAB_RHACS_SCHEDULES[@]}"; do
  CFG_ID="$(python3 -c '
import json,sys
name=sys.argv[1]
d=json.load(sys.stdin)
matches=[c for c in d.get("configurations",[]) if c.get("scanName")==name]
print(matches[0]["id"] if matches else "")
' "${name}" <<<"${CFG_JSON}")"

  if [[ -z "${CFG_ID}" ]]; then
    echo "  ${name}: not found in RHACS (ok)"
    continue
  fi

  HTTP_CODE="$(curl -sk -o /tmp/s3-cleanup-delete.out -w "%{http_code}" \
    -X DELETE "${AUTH_HEADER[@]}" \
    "${ROX_CENTRAL_ADDRESS}/v2/compliance/scan/configurations/${CFG_ID}")"
  if [[ "${HTTP_CODE}" == "200" || "${HTTP_CODE}" == "204" ]]; then
    echo "  ${name}: deleted from RHACS (${CFG_ID})"
  else
    echo "ERROR: RHACS DELETE ${name} failed (HTTP ${HTTP_CODE}): $(cat /tmp/s3-cleanup-delete.out)" >&2
    exit 1
  fi
done

echo "Removing lab ScanSettingBindings on the cluster..."
for name in "${LAB_BINDINGS[@]}"; do
  oc delete scansettingbinding "${name}" -n openshift-compliance --ignore-not-found
done

echo "Removing the lab tailored profile and custom rule..."
oc delete tailoredprofile org-namespace-owner -n openshift-compliance --ignore-not-found
oc delete customrule namespace-owner-label -n openshift-compliance --ignore-not-found

echo "Removing generated NetworkPolicies in backend..."
oc delete networkpolicy -l network-policy-generator.stackrox.io/generated=true \
  -n backend --ignore-not-found
oc delete networkpolicy stackrox-generated-postgres \
  -n backend --ignore-not-found 2>/dev/null || true

echo "Removing local compliance report artifacts from the bastion home (if present)..."
rm -f "${HOME}/compliance-report.zip" 2>/dev/null || true
rm -rf "${HOME}/compliance-report" 2>/dev/null || true

echo ""
echo "=== Cleanup checklist ==="
echo "RHACS scan schedules:"
curl -sk "${AUTH_HEADER[@]}" \
  "${ROX_CENTRAL_ADDRESS}/v2/compliance/scan/configurations" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); names=[c.get("scanName") for c in d.get("configurations",[])]; print(" ", ", ".join(names) if names else "(none)")'

echo "Cluster ScanSettingBindings:"
oc get scansettingbinding -n openshift-compliance 2>/dev/null \
  || echo "  (none)"

echo "Lab tailored profile and custom rule:"
oc get tailoredprofile org-namespace-owner -n openshift-compliance 2>/dev/null \
  || echo "  org-namespace-owner: not found (ok)"
oc get customrule namespace-owner-label -n openshift-compliance 2>/dev/null \
  || echo "  namespace-owner-label: not found (ok)"

echo "backend NetworkPolicies:"
oc get networkpolicy -n backend 2>/dev/null || echo "  (none)"

echo ""
echo "=== Session 3 cleanup complete ==="
