#!/usr/bin/env bash
# Session 2 cleanup script
# Removes lab-created resources so exercises can be run from scratch.
# Safe to run multiple times (idempotent).
#
# Usage:
#   bash scripts/s2-cleanup.sh all      # clean everything
#   bash scripts/s2-cleanup.sh 2        # clean Exercise 2 only
#   bash scripts/s2-cleanup.sh 3 5      # clean Exercises 3 and 5
#   bash scripts/s2-cleanup.sh          # (no args) same as all
#
# Arguments: 2  3  4  5  6  all
#
# Requires: ROX_CENTRAL_ADDRESS and ROX_API_TOKEN in the environment,
#           oc logged in to the cluster, and python3 available.

set -euo pipefail

# ── Parse flags ──

DO_ALL=false
DO_EX2=false DO_EX3=false DO_EX4=false DO_EX5=false DO_EX6=false

if [ $# -eq 0 ]; then
  DO_ALL=true
fi

for arg in "$@"; do
  case "$arg" in
    all)        DO_ALL=true ;;
    2)          DO_EX2=true ;;
    3)          DO_EX3=true ;;
    4)          DO_EX4=true ;;
    5)          DO_EX5=true ;;
    6)          DO_EX6=true ;;
    -h|--help|help)
      echo "Usage: bash scripts/s2-cleanup.sh [all] [2] [3] [4] [5] [6]"
      echo "  No arguments = all"
      exit 0
      ;;
    *) echo "Unknown argument: $arg (use help)"; exit 1 ;;
  esac
done

if $DO_ALL; then
  DO_EX2=true DO_EX3=true DO_EX4=true DO_EX5=true DO_EX6=true
fi

# ── Helpers ──

AUTH="Authorization: Bearer ${ROX_API_TOKEN}"
CENTRAL="${ROX_CENTRAL_ADDRESS}"

ok()    { printf "  %-44s %s\n" "$1" "deleted"; }
reset() { printf "  %-44s %s\n" "$1" "reset"; }
skip()  { printf "  %-44s %s\n" "$1" "not found, skipping"; }

lookup_policy()    { curl -sk -H "${AUTH}" "${CENTRAL}/v1/policies"              | python3 -c "import sys,json; [print(p['id']) for p in json.load(sys.stdin)['policies']        if '${1}' in p['name']]"  2>/dev/null | head -1; }
lookup_notifier()  { curl -sk -H "${AUTH}" "${CENTRAL}/v1/notifiers"             | python3 -c "import sys,json; [print(n['id']) for n in json.load(sys.stdin)['notifiers']       if '${1}' in n['name']]"  2>/dev/null | head -1; }
lookup_authprov()  { curl -sk -H "${AUTH}" "${CENTRAL}/v1/authProviders"          | python3 -c "import sys,json; [print(p['id']) for p in json.load(sys.stdin)['authProviders']   if '${1}' in p['name']]"  2>/dev/null | head -1; }
lookup_permset()   { curl -sk -H "${AUTH}" "${CENTRAL}/v1/permissionsets"         | python3 -c "import sys,json; [print(p['id']) for p in json.load(sys.stdin)['permissionSets']  if p['name']=='${1}']"    2>/dev/null | head -1; }
lookup_scope()     { curl -sk -H "${AUTH}" "${CENTRAL}/v1/simpleaccessscopes"     | python3 -c "import sys,json; [print(s['id']) for s in json.load(sys.stdin)['accessScopes']    if s['name']=='${1}']"    2>/dev/null | head -1; }
lookup_report()    { curl -sk -H "${AUTH}" "${CENTRAL}/v2/reports/configurations"  | python3 -c "import sys,json; [print(c['id']) for c in json.load(sys.stdin).get('reportConfigs',[]) if '${1}' in c['name']]" 2>/dev/null | head -1; }

delete_by_id() {
  local label="$1" endpoint="$2" id="$3"
  if [ -n "$id" ]; then
    curl -sk -X DELETE -H "${AUTH}" "${CENTRAL}${endpoint}/${id}" > /dev/null 2>&1
    ok "$label"
  else
    skip "$label"
  fi
}

reset_policy() {
  local label="$1" search="$2" disable="${3:-false}"
  local id
  id=$(lookup_policy "$search")
  if [ -n "$id" ]; then
    curl -sk -H "${AUTH}" "${CENTRAL}/v1/policies/${id}" | \
      DISABLE_POLICY="${disable}" python3 -c "
import sys,json,os
p=json.load(sys.stdin)
p['notifiers']=[]
if os.environ.get('DISABLE_POLICY')=='true':
    p['disabled']=True
p['exclusions']=[e for e in p.get('exclusions',[]) if not e.get('deployment',{}).get('scope',{}).get('namespace')]
print(json.dumps(p))
" | curl -sk -X PUT -H "${AUTH}" -H "Content-Type: application/json" -d @- "${CENTRAL}/v1/policies/${id}" > /dev/null 2>&1
    reset "$label"
  else
    skip "$label"
  fi
}

echo "Session 2 cleanup"
echo "================="

# ── Exercise 6: Splunk ──

if $DO_EX6; then
  echo ""
  echo "Exercise 6 (Splunk):"
  oc delete pod splunk-trigger-curl splunk-trigger-apk -n frontend --ignore-not-found 2>/dev/null && ok "splunk trigger pods" || skip "splunk trigger pods"
  delete_by_id "Lab - Curl in Image Splunk policy"           "/v1/policies"                        "$(lookup_policy 'Lab - Curl in Image Splunk')"
  delete_by_id "Lab - APK in Image Splunk policy"            "/v1/policies"                        "$(lookup_policy 'Lab - APK in Image Splunk')"
  delete_by_id "Lab - Splunk HEC notifier"                   "/v1/notifiers"                       "$(lookup_notifier 'Lab - Splunk HEC')"

  # Delete lab events from Splunk so previous test data does not confuse students
  oc exec deploy/splunk -n splunk -c splunk -- curl -sk -u admin:RhacsSplunkDemo123! \
    -X POST "https://localhost:8089/services/authorization/roles/admin" \
    -d "imported_roles=can_delete&imported_roles=power&imported_roles=user" \
    -o /dev/null 2>/dev/null
  oc exec deploy/splunk -n splunk -c splunk -- curl -sk -u admin:RhacsSplunkDemo123! \
    -X POST "https://localhost:8089/services/search/jobs" \
    -d 'search=search index=* sourcetype="stackrox-lab-alert" | delete' \
    -d "output_mode=json" -o /dev/null 2>/dev/null && ok "stackrox-lab-alert events in Splunk" || skip "stackrox-lab-alert events in Splunk"
fi

# ── Exercise 5: Webhook ──

if $DO_EX5; then
  echo ""
  echo "Exercise 5 (Webhook):"
  oc delete pod webhook-trigger -n backend --ignore-not-found 2>/dev/null && ok "webhook trigger pod" || skip "webhook trigger pod"
  delete_by_id "Lab - Latest tag webhook policy"             "/v1/policies"                        "$(lookup_policy 'Lab - Latest tag webhook')"
  delete_by_id "Lab - Webhook notifier"                      "/v1/notifiers"                       "$(lookup_notifier 'Lab - Webhook')"
fi

# ── Exercise 4: Risk/Deferral ──

if $DO_EX4; then
  echo ""
  echo "Exercise 4 (Risk/Deferral):"
  reset_policy "Fixable Severity at least Important"          "Fixable Severity at least Important"  false
fi

# ── Exercise 3: SAC/OIDC ──

if $DO_EX3; then
  echo ""
  echo "Exercise 3 (SAC/OIDC):"
  delete_by_id "Keycloak - rhacs-lab auth provider"          "/v1/authProviders"                   "$(lookup_authprov 'Keycloak - rhacs-lab')"
  curl -sk -X DELETE -H "${AUTH}" "${CENTRAL}/v1/roles/lab-payments-vuln-reader" > /dev/null 2>&1 && ok "lab-payments-vuln-reader role" || skip "lab-payments-vuln-reader role"
  delete_by_id "lab-vuln-reader permission set"              "/v1/permissionsets"                   "$(lookup_permset 'lab-vuln-reader')"
  delete_by_id "lab-payments-scope access scope"             "/v1/simpleaccessscopes"               "$(lookup_scope 'lab-payments-scope')"

  echo ""
  echo "Keycloak:"
  SSO_HOST="$(oc get route keycloak -n keycloak -o jsonpath='{.spec.host}' 2>/dev/null)" || true
  if [ -n "$SSO_HOST" ]; then
    KC_USER=$(oc -n keycloak get secret keycloak-initial-admin -o jsonpath='{.data.username}' | base64 -d)
    KC_PASS=$(oc -n keycloak get secret keycloak-initial-admin -o jsonpath='{.data.password}' | base64 -d)
    KC_TOKEN=$(curl -sk -X POST "https://${SSO_HOST}/realms/master/protocol/openid-connect/token" \
      -d "client_id=admin-cli&grant_type=password&username=${KC_USER}&password=${KC_PASS}" | \
      python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)
    if [ -n "$KC_TOKEN" ]; then
      HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -X DELETE -H "Authorization: Bearer ${KC_TOKEN}" "https://${SSO_HOST}/admin/realms/rhacs-lab")
      if [ "$HTTP_CODE" = "204" ]; then
        ok "rhacs-lab realm"
      else
        skip "rhacs-lab realm"
      fi
    else
      skip "rhacs-lab realm (auth failed)"
    fi
  else
    skip "Keycloak route not found"
  fi
fi

# ── Exercise 2: Reports ──

if $DO_EX2; then
  echo ""
  echo "Exercise 2 (Reports):"
  delete_by_id "Payments vulnerability report"               "/v2/reports/configurations"           "$(lookup_report 'Payments')"
fi

echo ""
echo "Cleanup complete."
