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
  `revoke`), `put-secret`, run folders (`targets.tsv`, a copy of `kyquickstart`, `kyq/`),
  agent launch per CLI, dashboard placement, handover after exit.
- Updates (`self_update`, `kyq_update` in `kyqs-ai`): on a terminal, `start` and `resume` offer
  to fast-forward this checkout, and `start` offers the latest KyQuickStart release binary when
  the one in use is older or missing. A binary is installed only after it matches GitHub's
  published digest and, with `gh`, the release attestation; development builds and resumed
  runs (which keep their own copy) are never replaced.
- `bin/prepare-host.sh`, `bin/revoke-host.sh`: the only root-run code; POSIX `sh`.
- `bin/on`, `bin/progress`, `bin/dashboard`, `bin/redact`, `bin/handover`: run-folder helpers.
- `bin/interview`: the launcher's setup form (PROMPT.md section 3 as screens and tick lists),
  writing `<run>/interview.yaml`; its app table follows PROMPT.md section 4. It runs only on a
  terminal; without one the agent sends its chat form.
- `README.md`: user guide. `CHANGELOG.md`: release notes.
- Releases are source only: the version is the git tag `vX.Y.Z`, with no VERSION file. Users
  run a clone, and `launch.txt` records `git describe --tags`. To release, add the
  `CHANGELOG.md` section, merge, and publish the GitHub release `vX.Y.Z` on `master`.

## Local Contracts

- Secret values never enter the agent's conversation: generated on servers, moved by pipe,
  supplied by the user through `put-secret`, resolved into the 0600 handover only by
  `bin/handover` after the agent exits. `handover.tsv` holds locations, never values.
- The agent's server login `kyops` is key-only (`restrict`), passwordless, sudo-less, in the
  `docker` group, owner of `/srv/ky`. Docs must say docker group is root-equivalent.
  `revoke` removes access and never touches apps or `/srv/ky`; it leaves an empty
  `<state>/revoked/kyq-<name>` so `hosts` can say so, and `add-host` removes that file.
- Install targets are `local` (this computer, no SSH, the agent runs as the user),
  `kyq-<name>` servers and `kube-<name>` clusters (a 0600 kubeconfig path, recorded in
  `<state>/clusters/`, usable only with kyquickstart; the agent never opens the file). The agent reaches every target through `bin/on`, so the prompt and
  hands-off allow-list are the same for both. Local mode never touches `~/.ssh`; `KYQS_DATA`
  exists only so tests can replace `/srv/ky`.
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

- `shellcheck -x kyqs-ai bin/* test/*.sh`
- `test/unit.sh`: progress, dashboard, redact, handover, the setup form (scripted keys).
- `test/e2e.sh`: needs Docker; disposable sshd container with a stub `docker`: add-host,
  pinning and tamper refusal, `--prepared`, add-cluster/remove-cluster with a stub
  kyquickstart, put-secret, handover, guided start with a stub agent (targets.tsv, kyquickstart
  copy and allow-list), a local-only start (no SSH), revoke and re-add.

## Child DOX Index

None.
