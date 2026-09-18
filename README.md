# ACS hands-on labs

Antora content for Red Hat Advanced Cluster Security (RHACS) customer sessions, published with the Red Hat Demo Platform Showroom UI.

**Live site:** https://john-johansson.github.io/acs-labs/modules/index.html

```text
content/modules/ROOT/pages/     AsciiDoc lab instructions
content/modules/ROOT/examples/  YAML attendees apply from the bastion
site.yml                        Antora playbook (RHDP Showroom theme)
```

Build locally with Node.js 22:

```bash
npm i -g @antora/cli@3.1 @antora/site-generator@3.1
antora --fetch site.yml
```

Output is written to `www/`.
