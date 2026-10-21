# KyQuickStart AI

Suite-wide rules (security promises, KyRecovery contract, admin/everyday separation,
third-party admission) live in the busnes.app workspace `AGENTS.md` and in
`Busnes-app/KyQuickStart`'s `AGENTS.md`. This file owns only this repository.

## Purpose

Install the Ky suite by prompting a local AI agent, and use each run to test the product
READMEs. The deliverables of a run are the installed suite, a handover sheet, `feedback.md`
(README findings) and `install-guide-draft.md`.

## Ownership

- `PROMPT.md`: what the agent does and in what order; the feedback report format.
- `kyqs-ai`: launcher. Targets (`add-local`, `add-host`, `revoke`), `put-secret`, run folders,
  agent launch per CLI, dashboard placement, handover after exit.
- `bin/prepare-host.sh`, `bin/revoke-host.sh`: the only root-run code; POSIX `sh`.
- `bin/on`, `bin/progress`, `bin/dashboard`, `bin/redact`, `bin/handover`: run-folder helpers.
- `README.md`: user guide.

## Local Contracts

- Secret values never enter the agent's conversation: generated on servers, moved by pipe,
  supplied by the user through `put-secret`, resolved into the 0600 handover only by
  `bin/handover` after the agent exits. `handover.tsv` holds locations, never values.
- The agent's server login `kyops` is key-only (`restrict`), passwordless, sudo-less, in the
  `docker` group, owner of `/srv/ky`. Docs must say docker group is root-equivalent.
  `revoke` removes access and never touches apps or `/srv/ky`; it leaves an empty
  `<state>/revoked/kyq-<name>` so `hosts` can say so, and `add-host` removes that file.
- Install targets are `local` (this computer, no SSH, the agent runs as the user) and
  `kyq-<name>` servers. The agent reaches every target through `bin/on`, so the prompt and
  hands-off allow-list are the same for both. Local mode never touches `~/.ssh`; `KYQS_DATA`
  exists only so tests can replace `/srv/ky`.
- Host keys are pinned per alias in `~/.ssh/kyquickstart-ai/known_hosts`; a changed key is
  refused. The fingerprint comes from the server over the admin's own login or from the user.
- Commands sent through an admin's login shell are base64 only, so fish/zsh/bash cannot
  reinterpret them.
- The progress log is six tab-separated fields: epoch, clock, phase, item, state, note.
- The prompt never claims a third-party app is admitted; product facts in it are leads to
  verify at the release tag, and confirmed ones are README findings.
- Destructive steps need explicit user approval; the prompt states this, the tools do not
  enforce it, and the README says so.

## Work Guidance

- Keep the launcher bash 3.2 compatible (macOS) and the root-run scripts POSIX `sh`.
- When a product's install path changes, update `PROMPT.md` leads, not product docs here.

## Verification

- `shellcheck -x kyqs-ai bin/* test/*.sh`
- `test/unit.sh`: progress, dashboard, redact, handover.
- `test/e2e.sh`: needs Docker; disposable sshd container with a stub `docker`: add-host,
  pinning and tamper refusal, `--prepared`, put-secret, handover, guided start with a stub
  agent, a local-only start (no SSH), revoke and re-add.

## Child DOX Index

None.
