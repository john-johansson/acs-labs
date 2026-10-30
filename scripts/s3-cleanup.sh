#!/usr/bin/env bash
# Session 3: Compliance & Network Observability cleanup
# Idempotent: safe to run multiple times.

set -euo pipefail

echo "=== Session 3 cleanup ==="

# Compliance resources
echo "Removing ScanSettingBinding..."
oc delete scansettingbinding cis-weekly-scan -n openshift-compliance --ignore-not-found

echo "Waiting for ComplianceSuite deletion (follows ScanSettingBinding)..."
oc delete compliancesuite --all -n openshift-compliance --ignore-not-found 2>/dev/null || true

# Network policies generated during the lab
echo "Removing generated NetworkPolicies..."
oc delete networkpolicy -l network-policy-generator.stackrox.io/generated=true \
  -n qual-payments-ns --ignore-not-found
oc delete networkpolicy stackrox-generated-payment-db \
  -n qual-payments-ns --ignore-not-found 2>/dev/null || true

# Test pods used for anomalous flow simulation
echo "Removing test pods..."
oc delete pod --all -n test-sandbox --ignore-not-found 2>/dev/null || true

echo "=== Session 3 cleanup complete ==="
