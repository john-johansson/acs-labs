#!/usr/bin/env bash
# Summarize the compliance CSV downloaded by s3-fetch-compliance-report.sh.
# Color is used when stdout is a terminal. Set NO_COLOR=1 to disable it.

set -euo pipefail

CSV="$(find "${HOME}/compliance-report" -name '*.csv' 2>/dev/null | head -1 || true)"
if [[ -z "${CSV}" ]]; then
  echo "ERROR: no CSV under ${HOME}/compliance-report. Run scripts/s3-fetch-compliance-report.sh first." >&2
  exit 1
fi

python3 - "${CSV}" <<'PY'
import csv
import os
import sys
from collections import Counter

path = sys.argv[1]
use_color = sys.stdout.isatty() and not os.environ.get("NO_COLOR")

def paint(code, text):
    if not use_color:
        return text
    return f"\033[{code}m{text}\033[0m"

STATUS_COLOR = {
    "FAIL": "1;31",
    "ERROR": "1;35",
    "INCONSISTENT": "1;33",
    "MANUAL": "36",
    "PASS": "32",
    "NOT-APPLICABLE": "2",
}

def status_label(status, width=16):
    label = f"{(status or '(blank)'):<{width}}"
    return paint(STATUS_COLOR.get(status, "0"), label)

with open(path, newline="", encoding="utf-8", errors="replace") as handle:
    rows = list(csv.DictReader(handle))
if not rows:
    sys.exit("CSV has no data rows")

counts = Counter(row.get("Status") or "" for row in rows)
order = ["FAIL", "ERROR", "INCONSISTENT", "MANUAL", "PASS", "NOT-APPLICABLE"]
seen = set(order)
extras = sorted(status for status in counts if status not in seen)

print(paint("1", "Compliance report"))
print(f"  file:  {path}")
print(f"  rows:  {len(rows)}")
print()
print(paint("1", "Status counts"))
for status in order + extras:
    if status not in counts:
        continue
    print(f"  {status_label(status)} {counts[status]:>5}")

print()
print(paint("1", "Columns"))
print("  " + ", ".join(rows[0].keys()))

for status in ("FAIL", "INCONSISTENT"):
    hits = [row for row in rows if row.get("Status") == status][:5]
    if not hits:
        continue
    print()
    print(paint("1", f"Sample {status}"))
    for row in hits:
        print(f"  {status_label(status)} {row.get('Check(CCR)')}")
        print(f"  {'':<16} {row.get('Profile(version)')}")
PY
