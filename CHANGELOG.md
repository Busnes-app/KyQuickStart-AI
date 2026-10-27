# Changelog

Releases are source only and tagged `vX.Y.Z` on `master`. There is no built artifact: you run
a clone, and `./kyqs-ai` offers to fast-forward it at start. A run records the checkout's
`git describe --tags` in `launch.txt`.

## Unreleased

- Select `KYQS_STRONG_KUBE_TLS=1` to require verified, strong peer certificates
  for launcher-owned Kubernetes onboarding and revocation. The profile needs
  a standard Go 1.24+ kubectl release build; existing strong credentials and
  ServiceAccount permissions are retained. See `docs/STRONG-KUBERNETES-TLS.md`
  for client-credential review and independent transport requirements.
- Refuse insecure/non-HTTPS kubeconfigs before strong-profile onboarding or
  revocation; a CLI false flag alone does not override an insecure kubeconfig.
  Check the actual client under its selected crypto mode and use the pinned
  qualified client for real-cluster CI.
- Native TLS regressions check weak leaf/intermediate/root refusal before
  administrative HTTP, with strong and ordinary trust-failure controls.

## 0.6.0 — 2026-10-26

### Changed

- Launcher and remote helpers require OpenSSH 9.1+ and RSA-2048 endpoint keys, exclude
  obsolete negotiation algorithms and bypass existing control masters. A reviewed SSH
  profile can retain strong administrator certificates while excluding weak CAs. Existing
  keys, server pins and application data are retained; see `docs/STRONG-SSH.md` before upgrading.
- `add-cluster <name> <admin-kubeconfig>` now creates a ServiceAccount `kyqs-ai/kyqs-ai-<name>`
  bound to the permissions `kyquickstart preflight` checks, plus `pods/log`, and hands the
  agent only its kubeconfig. Before, the agent's kubeconfig was the one you gave, often
  cluster-admin. Clusters added by 0.5.0 show as not ready until you run `add-cluster` again.
- `revoke kube-<name> <admin-kubeconfig>` deletes that ServiceAccount and its rights. `kubectl`
  is needed for both.
- `put-secret` strips leading and trailing whitespace and blank lines, and refuses an empty
  secret. A pasted leading blank line had broken `Authorization: Bearer $(cat file)`.
- The prompt checks digest pinning by comparing each container's image ID with the pinned
  reference's (`docker ps` shows only the tag on Docker 29), and checks shell-less images
  (KyNotes, MAS) from outside.

## 0.5.0 — 2026-10-23

First release, after five complete install runs.

### What it does

- `./kyqs-ai` installs the Ky suite with the AI coding agent you already use: Claude Code,
  Codex CLI, Gemini CLI or opencode. The agent plans and diagnoses, and KyQuickStart's
  `kyquickstart` binary deploys and operates every catalog product on Docker (Compose over
  SSH) or Kubernetes.
- Targets: this computer (`add-local`), servers over SSH (`add-host`) and Kubernetes clusters
  (`add-cluster`).
- A setup form, one question per screen with tick lists and a review screen, replaces the
  chat interview. The answers go to `interview.yaml`.
- A live status board (`./kyqs-ai dashboard`, or a tmux side pane on every run) shows phases,
  apps, recent events, a **NEEDS YOU** banner and a quiet-for-10-minutes warning.
- At the end, `bin/handover` builds a 0600 sheet of URLs, administrator and everyday logins,
  read straight from the servers after the agent exits. The run also leaves `feedback.md`,
  `install-guide-draft.md`, `state.md` and the `kyq/` plan for later operations.
- With your approval of each redacted issue, the agent files the Ky product problems it found
  as GitHub issues.
- At start, the launcher offers to update itself (`git pull --ff-only`) and to download the
  latest `kyquickstart` release. The download must match GitHub's published digest and, with
  `gh`, the release's build attestation.

### Security model

- The agent logs in to servers as `kyops`: key-only (`restrict`), no password, no `sudo`, owner
  of `/srv/ky`. Being in the `docker` group makes it root-equivalent, which the README says.
  `./kyqs-ai revoke <name>` removes its access and leaves apps and data in place.
- Host keys are pinned per server, and a changed key is refused. Each run gets its own
  ssh-agent holding only the KyQuickStart AI key.
- Secrets are generated on the servers and moved by pipe. You supply your own secrets with
  `put-secret`. The agent's logs pass through a redaction filter.
- Hands-off mode (Claude Code, Codex) pre-approves the commands an install uses. The README
  lists exactly what it allows. Supervised mode asks before each command.

### Known limitations

- No third-party app has completed suite admission, so each one is labelled a test install.
- The launcher tests use stub Docker, agent and `kyquickstart` commands. Product deployment,
  lifecycle and restore are tested in KyQuickStart (`make e2e`).
- "Ask before anything destructive" is a prompt instruction. No tool enforces it.
- Podman is not supported. Docker Engine with the compose plugin must already be installed.
