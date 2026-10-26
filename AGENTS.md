# KyQuickStart AI

Suite-wide rules (security promises, KyRecovery contract, admin/everyday separation,
third-party admission) live in the busnes.app workspace `AGENTS.md` and in
`Busnes-app/KyQuickStart`'s `AGENTS.md`. This file owns only this repository.

## Purpose

The primary installation path for the Ky suite (owner decision 2026-10-22): a local AI agent
plans, converses and diagnoses; `kyquickstart` (Busnes-app/KyQuickStart) executes catalog
installs and ongoing operations on Docker over SSH and Kubernetes. Third-party apps and the
`local` target follow product READMEs. The deliverables of a run are the installed suite, its
`kyq/` plan, a handover sheet, `feedback.md` (README and kyquickstart findings) and
`install-guide-draft.md`. KyQuickStart's `docs/redirect.md` is the redirect record.

## Ownership

- `PROMPT.md`: what the agent does and in what order; the feedback report format.
- `kyqs-ai`: launcher. Targets (`add-local`, `add-host`, `add-cluster`, `remove-cluster`,
  `revoke`, including a cluster's ServiceAccount), `put-secret`, run folders (`targets.tsv`, a copy of `kyquickstart`, `kyq/`),
  agent launch per CLI, dashboard placement, handover after exit.
- Updates (`self_update`, `kyq_update` in `kyqs-ai`): on a terminal, `start` and `resume` offer
  to fast-forward this checkout, and `start` offers the latest KyQuickStart release binary when
  the one in use is older or missing. A binary is installed only after it matches GitHub's
  published digest and, with `gh`, the release attestation; development builds and resumed
  runs (which keep their own copy) are never replaced.
- `bin/prepare-host.sh`, `bin/revoke-host.sh`: the only root-run code; POSIX `sh`.
- `bin/on`, `bin/progress`, `bin/dashboard`, `bin/redact`, `bin/handover`: run-folder helpers.
- `bin/ssh-policy`: shared transport policy for every launcher/helper SSH call; copied into
  new runs. `docs/STRONG-SSH.md` owns the supported administrator key/CA profile and scope.
- `bin/interview`: the launcher's setup form (PROMPT.md section 3 as screens and tick lists),
  writing `<run>/interview.yaml`; its app table follows PROMPT.md section 4. It runs only on a
  terminal; without one the agent sends its chat form.
- `README.md`: user guide. `CHANGELOG.md`: release notes. `CONTRIBUTING.md`: process, test
  policy and coding standard.
- `docs/ASSURANCE-CASE.md`: threat model, trust boundaries, what the hands-off allow-list does
  and does not stop, weaknesses table; updated by any change to a trust boundary or the
  allow-list. `docs/VERIFYING-RELEASES.md`: checking a release tag's GitHub-signed commit.
- Releases are source only: the version is the git tag `vX.Y.Z`, with no VERSION file. Users
  run a clone, and `launch.txt` records `git describe --tags`. To release, add the
  `CHANGELOG.md` section, merge, and publish the GitHub release `vX.Y.Z` on `master`.

## Local Contracts

- Secret values never enter the agent's conversation: generated on servers, moved by pipe,
  supplied by the user through `put-secret`, resolved into the 0600 handover only by
  `bin/handover` after the agent exits. `handover.tsv` holds locations, never values.
  `put-secret` keeps the value off argv and out of output, trims surrounding whitespace and
  refuses an empty one.
- The agent's server login `kyops` is key-only (`restrict`), passwordless, sudo-less, in the
  `docker` group, owner of `/srv/ky`. Docs must say docker group is root-equivalent.
  `revoke` removes access and never touches apps or `/srv/ky`; it leaves an empty
  `<state>/revoked/kyq-<name>` so `hosts` can say so, and `add-host` removes that file.
- Install targets are `local` (this computer, no SSH, the agent runs as the user),
  `kyq-<name>` servers and `kube-<name>` clusters, usable only with kyquickstart. The agent
  reaches `local` and every server through `bin/on`, so the prompt and hands-off allow-list are
  the same for both. Local mode never touches `~/.ssh`; `KYQS_DATA` exists only so tests can
  replace `/srv/ky`.
- A cluster's agent credential is the ServiceAccount `kyqs-ai/kyqs-ai-<name>`, which
  `add-cluster` creates with the user's admin kubeconfig (never recorded) and `kubectl apply`
  (idempotent). Its ClusterRole of the same name is exactly KyQuickStart's preflight
  `required` list plus `get pods/log`, cluster-wide; it changes when that list does. Its
  kubeconfig is `<state>/clusters/kube-<name>` (0600; the agent never opens it), written only
  once the token works. Docs must say pod create plus Secret get everywhere can escalate.
  `revoke kube-<name> <admin-kubeconfig>` deletes binding, role, token and ServiceAccount, in
  that order, empties that file and leaves `<state>/revoked/kube-<name>`; `add-cluster`
  removes it. Add-host names may not start with `kube-`.
- Host keys are pinned per alias in `~/.ssh/kyquickstart-ai/known_hosts`; a changed key is
  refused. The fingerprint comes from the server over the admin's own login or from the user.
  `targets.tsv` hands that fingerprint to kyquickstart's `--trust-host-key`; kyquickstart pins
  it in its own state. kyquickstart authenticates only through ssh-agent, so each run gets its
  own agent (short socket under `/tmp`) holding this key alone, stopped on exit. Claude
  hands-off settings deny `Read` on every registered kubeconfig.
- Catalog products on `kyq-*` and `kube-*` targets go through `./bin/kyquickstart --state
  ./kyq` only; the agent writes only `kyq/stack.yaml` and never bypasses a refusal by hand.
  `KYQS_KYQUICKSTART` overrides the binary (empty: none, README installs only).
- Commands sent through an admin's login shell are base64 only, so fish/zsh/bash cannot
  reinterpret them.
- Route product-owned SSH through `bin/ssh-policy`: require the actual client's RSA-2048
  option, retain maintained algorithms after exclusions and bypass old control masters.
  `KYQS_SSH_CONFIG` selects an explicit reviewed profile; certificate-signing CA size is a
  separate review, not enforced by OpenSSH's endpoint-size option. Retain strong credentials.
- The progress log is six tab-separated fields: epoch, clock, phase, item, state, note.
- The prompt never claims a third-party app is admitted; product facts in it are leads to
  verify at the release tag, and confirmed ones are README findings.
- Ky product findings go to `Busnes-app/<repo>` as GitHub issues only with the user's
  approval of each redacted issue; third-party findings stay in `feedback.md`.
- Destructive steps need explicit user approval; the prompt states this, the tools do not
  enforce it, and the README says so.

## Work Guidance

- Keep the launcher bash 3.2 compatible (macOS) and the root-run scripts POSIX `sh`.
- When a product's install path changes, update `PROMPT.md` leads, not product docs here.

## Verification

- Scorecard (`.github/workflows/scorecard.yml`) publishes public supply-chain security results on default-branch pushes, weekly and after branch-protection changes. Keep publishing restricted to the default branch, action pins immutable, checkout credentials disabled and OIDC/code-scanning writes scoped to the analysis job. README’s live Scorecard badge needs a successful published run.

- `shellcheck -x kyqs-ai bin/* test/*.sh`
- `test/unit.sh`: progress, dashboard, redact, handover, the setup form (scripted keys).
- `test/unit.sh` also covers put-secret's trimming and empty refusal.
- `test/unit.sh` checks effective SSH policy and capability refusal on Linux/macOS.
- `test/ssh-policy.sh`: real handshakes using the image built by `test/e2e.sh`; weak raw and
  certificate subjects, obsolete negotiation, strong controls, old master bypass and the
  separately reviewed CA profile. CI runs it after e2e.
- `test/e2e.sh`: needs Docker; disposable sshd container with a stub `docker`: add-host,
  pinning and tamper refusal, `--prepared`, add-cluster/revoke/remove-cluster with stub
  kyquickstart and kubectl, put-secret, handover, guided start with a stub agent (targets.tsv,
  kyquickstart copy and allow-list), a local-only start (no SSH), revoke and re-add.
- `test/kube.sh`: needs kubectl and kind (or `KYQS_TEST_KUBECONFIG` for a disposable cluster):
  the ServiceAccount's allowed and denied rights, re-run and repair, revoke and re-add;
  with `KYQS_TEST_KYQUICKSTART`, a real `kyquickstart preflight`. CI's `kube` job runs it.

## Child DOX Index

None.
