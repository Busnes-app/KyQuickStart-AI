# During and after a run

[Product overview](../README.md)

Commands and unlinked file paths below are relative to the repository root.

## While it works

The dashboard (`./kyqs-ai dashboard` in a second terminal, or the tmux side pane) shows each
phase and app, what the agent is doing, recent events, and a **NEEDS YOU** banner when it is
waiting for you. If it goes quiet for 10 minutes, the board says so. When the board is taller
than the window, it hides finished items first, then older events.

When the agent needs a secret from you (for example a DNS API token), it does not ask in chat.
It gives you a command that stores it straight on the server:

```sh
./kyqs-ai put-secret kyq-<name> /srv/ky/<app>/secrets/<file>   # hidden input, stored 0600
```

It strips leading and trailing spaces and blank lines from what you paste, stores the rest
without a final newline, and refuses an empty secret. You can also pipe the value in.

## Secrets

- The prompt has the agent generate secrets on the servers and move them by pipe, so the
  values stay out of its conversation and your AI provider. This is an instruction the agent
  follows, not a barrier: an agent that ignores it can read them. Logs it reads pass through
  a redaction filter as a backstop, and the prompt tells it to report any secret it sees.
- The handover sheet is assembled by [`bin/handover`](../bin/handover) after the agent exits,
  reading each secret straight from its server into a file only you can read (mode 0600).
  Save the logins in a password manager, then `shred -u` the file.
- The run folder is `~/.local/state/kyquickstart-ai/runs/<time>/` (mode 0700).

## What you get

| File in the run folder | Contents |
|---|---|
| `handover.txt` | URLs, administrator and everyday logins, break-glass admins, remaining manual steps |
| `feedback.md` | Run report: what worked, what failed, and the README changes each repo needs |
| `install-guide-draft.md` | The install sequence that worked, written for a newcomer |
| `state.md` | The plan, decisions and everything created, for resuming and auditing |
| `kyq/` | kyquickstart's plan (`stack.yaml`) and results; no secrets. Keep it: later runs operate the same installation from it |
| `targets.tsv` | Each target's address, port, login and pinned host key, or kubeconfig path |
| `progress.log` | The dashboard's event log |

## Verification and readiness

The launcher tests check launcher behavior, secret redaction, host-key handling, cluster
registration and handover mechanics. `test/kube.sh` checks the cluster ServiceAccount's
rights, re-runs and revoke on a real kind cluster, and runs `kyquickstart preflight` with it. The end-to-end harness uses disposable SSH
infrastructure and a stub Docker command, agent and kyquickstart; it is **not a full
Ky-product install or recovery test**. Product deployment, ownership, lifecycle and restore
are tested in KyQuickStart (`make e2e`).

Read each run’s `feedback.md`, `state.md` and handover before using the installation.
Require separate observed evidence for email send/receive and verification links, real
MFA approval, product access/offboarding, backup deposits, blob/bulk coverage, custodian
card distribution and a scratch restore with the actual cards. A generated handover,
screenshot, successful health response or synthetic recovery drill proves only its own
scope. Keep passwords and real recovery shares out of public reports and promo images.
