#!/usr/bin/env bash
# Session 3: Compliance & Network Observability cleanup
# Idempotent: safe to run multiple times.

set -euo pipefail

echo "=== Session 3 cleanup ==="

# Compliance resources (lab-created bindings from Exercises 1 and 2)
# Does not restore CIS profiles into acs-catch-all (instructor prep owns that).
echo "Removing ScanSettingBinding cis-weekly-scan..."
oc delete scansettingbinding cis-weekly-scan -n openshift-compliance --ignore-not-found
echo "Removing ScanSettingBinding cis-audit-schedule..."
oc delete scansettingbinding cis-audit-schedule -n openshift-compliance --ignore-not-found

# Network policies generated during the lab
echo "Removing generated NetworkPolicies in backend..."
oc delete networkpolicy -l network-policy-generator.stackrox.io/generated=true \
  -n backend --ignore-not-found
oc delete networkpolicy stackrox-generated-postgres \
  -n backend --ignore-not-found 2>/dev/null || true

echo "=== Session 3 cleanup complete ==="
