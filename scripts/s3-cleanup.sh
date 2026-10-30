#!/usr/bin/env bash
# Session 3: Compliance & Network Observability cleanup
# Idempotent: safe to run multiple times.

set -euo pipefail

echo "=== Session 3 cleanup ==="

# Compliance resources (only the lab-created binding)
echo "Removing ScanSettingBinding cis-weekly-scan..."
oc delete scansettingbinding cis-weekly-scan -n openshift-compliance --ignore-not-found

# Network policies generated during the lab
echo "Removing generated NetworkPolicies in backend..."
oc delete networkpolicy -l network-policy-generator.stackrox.io/generated=true \
  -n backend --ignore-not-found
oc delete networkpolicy stackrox-generated-postgres \
  -n backend --ignore-not-found 2>/dev/null || true

echo "=== Session 3 cleanup complete ==="
