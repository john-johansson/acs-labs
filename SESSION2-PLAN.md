# Session 2: Operations & Day-2

90 to 95 minute hands-on lab. CTIE platform and security engineers. Standalone (no Session 1 dependency). Same Showroom environment.

## Decisions

* Notifiers: Generic Webhook + Splunk (Jira and live OpenITCockpit are discussion-only).
* Structure: six exercise slots. SAC and OIDC are merged so Risk and CVE deferral fit without a seventh timed block.
* Source of truth for student steps: Antora `s2-*.adoc` pages.

## Session flow

| # | Exercise | Topic | Time | Status |
|---|----------|-------|------|--------|
| 1 | Vulnerability dashboard and Scanner V4 | Vulnerability Management | 15 min | Verified on Showroom |
| 2 | Automated vulnerability reports (PDF/CSV) | Vulnerability Management | 15 min | On-demand download (no schedule without SMTP) |
| 3 | SAC and OIDC group mapping | RBAC and Identity | 20 min | Keycloak verified; 4.11 permission resources |
| 4 | Risk profiling and CVE deferral | Risk and exceptions | 15 min | Risk + exclusion verified; new deferral create flaky |
| 5 | Webhook notifier | Notifiers | 15 min | webhook.site verified |
| 6 | Splunk HEC integration | Notifiers | 15 min | HEC verified |

**Total: ~95 min including 5 min prereqs**

## Live verify notes (cluster-sz6zn)

* ACS version: 4.11.5. Cluster name in ACS: `production`.
* Namespaces present: `payments`, `backend`, `frontend`, `juice-shop`, `log4shell`, `apache-struts`. No `policy-lab`.
* High-priority demo workload for Risk: `juice-shop`.
* Vulnerability exceptions list works. Sample Deferred and False positive exceptions already exist. Creating a *new* deferral via GraphQL failed on this build; Ex 4 uses review of existing exceptions as the required path.
* Scheduled vulnerability reports require an email notifier. Download-only reports must leave Schedule empty, then Generate with download.
* Permission set resources in 4.11 do not include `Policy` / `Administration` / `Integration` names from older docs. Use `Image`, `Deployment`, `Alert`, `CVE`, `WatchedImage`.
* Keycloak lab users need Email verified On and no Required user actions, or login fails with `Account is not fully set up`.
* Auth providers out of the box: basic (+ monitoring userpki). Students create Keycloak OIDC.
* Keycloak `temp-admin` login works.
* Policy `Latest tag` enabled (webhook trigger). Splunk trigger: students enable *Curl in Image* and *Alpine Linux Package Manager (apk) in Image*, attach HEC, then run `curlimages/curl` and `alpine:3.18`.
* Splunk route and HEC token retrieval work. Existing notifier name may be `Splunk SIEM (local)`.
* webhook.site reachable over HTTPS.

## Adaptations from WIP Session 2 PDF

| PDF item | Lab adaptation |
|----------|----------------|
| Ex 1 combined reports + Scanner V4 | Split into Antora Ex 1 + Ex 2 for timing |
| Ex 2 SAC + SSO | Antora Ex 3 (merged SAC + OIDC). Console Plugin is optional tip only |
| Ex 3 Risk + deferral | Antora Ex 4 |
| Ex 4 Webhook + Jira | Webhook kept. Jira omitted (not in Showroom). Splunk kept as Ex 6 |
| Ex 5 Developer Loop | Short discussion block on overview and summary, not a timed exercise |
| SBOM via `roxctl image metadata` | Omitted until bastion command path is confirmed for all students |

## Antora files

| File | Role |
|------|------|
| `pages/operations-day2.adoc` | Overview |
| `pages/s2-01-prerequisites.adoc` | Prereqs |
| `pages/s2-02-vuln-dashboard.adoc` | Exercise 1 |
| `pages/s2-03-vuln-reports.adoc` | Exercise 2 |
| `pages/s2-04-sac-oidc.adoc` | Exercise 3 |
| `pages/s2-05-risk-deferral.adoc` | Exercise 4 |
| `pages/s2-06-webhook.adoc` | Exercise 5 |
| `pages/s2-07-splunk.adoc` | Exercise 6 |
| `pages/s2-08-summary.adoc` | Summary |
| `nav.adoc` | Operations & Day-2 section |
