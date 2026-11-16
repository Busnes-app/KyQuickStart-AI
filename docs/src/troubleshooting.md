# Troubleshooting

- **No supported agent detected:** install/configure one of the CLIs listed in the product reference and retry.
- **SSH fingerprint changed:** stop and verify it through your own trusted administrator connection; do not accept it blindly.
- **Permission problem on a target:** check host preparation and Docker access. Membership in the Docker group grants root-equivalent control.
- **Dashboard says done but an app fails:** inspect the recorded verification; launcher completion is not product readiness.
- **Secret needed:** use `put-secret`; keep the value out of chat and progress notes.
- **Installation incomplete:** preserve the run record and inspect feedback before repeating steps against existing services.

When reporting a problem, include the product version, platform, failed task and a redacted error. Exclude pairing links, device secrets, recovery codes, custodian shares and private content.
