# KyQuickStart AI

[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/15933/badge)](https://www.bestpractices.dev/projects/15933)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/Busnes-app/KyQuickStart-AI/badge)](https://scorecard.dev/viewer/?uri=github.com/Busnes-app/KyQuickStart-AI)

Install and run the Ky suite with the AI coding agent you already use. This is the primary
way to install the suite. `kyqs-ai` connects your servers over SSH and your Kubernetes
clusters, starts the agent with an installation prompt, shows a live status board while it
works, and gives you a printable sheet of URLs, logins and passwords at the end.

The agent plans with you, talks you through choices and diagnoses problems.
[KyQuickStart](https://github.com/Busnes-app/KyQuickStart)'s `kyquickstart` binary does the
work for every catalog product: it validates the plan, deploys on Docker (Compose over SSH) or
Kubernetes, configures each product through its own setup command, keeps secrets on the
targets, refuses anything it does not own and verifies the result. The agent also uses it
afterwards to show status and logs, stop, start, restart, reconfigure, upgrade, remove
(keeping data), back up and restore. Third-party apps, and installs on this computer, follow
each product's README.

The agent creates separate **administrator** and **everyday** users, configures selected
identity/backup/monitoring integrations, and reports the outcome. Completion depends on
product readiness, supplied services and observed checks; launching an agent does not
guarantee these steps succeeded.

**Status:** v0.5.0 is the first release, after five complete install runs. No third-party app
has completed suite admission yet, so the agent labels each one a test install. Each run's
`feedback.md` records README and kyquickstart gaps.

## What you need

- **Your computer:** Linux or macOS with `bash`, OpenSSH 9.1 or later, `git`, the `kyquickstart` binary on
  your `PATH` (or `KYQS_KYQUICKSTART=/path/to/kyquickstart`; build it from
  [KyQuickStart](https://github.com/Busnes-app/KyQuickStart) with `make build`; KyYard needs a
  release binary), an SSH agent for the servers, and one supported agent CLI:
  [Claude Code](https://docs.claude.com/en/docs/claude-code) (`claude`),
  [Codex CLI](https://github.com/openai/codex) (`codex`),
  [Gemini CLI](https://github.com/google-gemini/gemini-cli) (`gemini`) or
  [opencode](https://opencode.ai) (`opencode`). `tmux` is optional; with it the dashboard opens beside the agent (`kyqs-ai` starts a tmux session when you are not in one).
- **Where the apps run:** this computer, servers, Kubernetes clusters, or a mix. Servers and
  this computer need Linux with Docker Engine and the compose plugin already installed (Podman
  is not supported); servers need a login that can use `sudo` (once, [below](docs/TARGETS.md#connecting-your-servers-over-ssh)). Clusters need an
  admin kubeconfig, `kubectl` on your computer (once, [below](docs/TARGETS.md#kubernetes-clusters)) and a persistent StorageClass.
  Nothing installs Docker or Kubernetes for you.
  x86-64 is what the suite targets. Which product runs where:
  [KyQuickStart docs/redirect.md](https://github.com/Busnes-app/KyQuickStart/blob/master/docs/redirect.md).
- **A domain you control.** The apps need HTTPS hostnames (passkeys and sign-in require it).
  LAN-only is fine; public DNS records may point at private addresses.

## Start

```sh
git clone https://github.com/Busnes-app/KyQuickStart-AI.git
cd KyQuickStart-AI
./kyqs-ai
```

The launcher walks you through:

1. **Where to install.** This computer, one or more servers, or both. For each server give a
   short name, its address and your admin login.
2. **Agent.** It picks from the agents installed on your computer, and for Claude Code and Codex
   asks whether to run hands-off ([below](docs/AGENT-PERMISSIONS.md#hands-off-mode)).
3. **Setup form.** One question per screen: domain, apps, who reaches them, proxy and
   certificates, placement, the admin and everyday accounts, the recovery ceremony and mail.
   Lists are ticked with Space and confirmed with Enter (↑/↓ move, q quits); a review screen
   lets you change any answer before the agent starts. The answers go to the run's
   `interview.yaml`.
4. **The run.** The agent reads your answers, checks the servers, and shows a plan. After you say "go" it works on its own, and only comes back for
   steps a person must do, batched together.
5. **Handover.** When you exit the agent, the launcher builds the handover sheet and offers to
   show and print it.

Continue an interrupted run with `./kyqs-ai resume`; the run keeps its own copy of
`kyquickstart`, so a resume uses the same version. See all commands with `./kyqs-ai help`.

## Upgrade

```sh
./kyqs-ai upgrade
```

Run it on the computer and clone that did the install. It updates this clone, downloads the
newest `kyquickstart` release into the latest run (or the run folder you name) and starts that
run's agent. The agent shows which apps change, asks before any upgrade without a backup, then
upgrades, verifies and updates the handover.

## Security and releases

- [Assurance case](docs/ASSURANCE-CASE.md): what the agent can and cannot reach, the threat
  model, and which protections are enforced and which are prompt instructions.
- [Verifying releases](docs/VERIFYING-RELEASES.md): check that your clone is at a release's
  GitHub-signed commit.
- Report vulnerabilities privately, per the
  [Busnes-app security policy](https://github.com/Busnes-app/.github/blob/main/SECURITY.md).

## Development

[CONTRIBUTING.md](CONTRIBUTING.md) has the process, test policy and coding standard.

```sh
shellcheck -x kyqs-ai bin/* test/*.sh
test/unit.sh      # progress, dashboard, redact, handover, put-secret
test/e2e.sh       # needs Docker: add-host, key pinning, put-secret, handover, revoke
test/kube.sh      # needs kubectl and kind: the cluster ServiceAccount, its rights and revoke
```

## License

MIT. See [LICENSE.txt](LICENSE.txt).

[![OctoCounts](https://api.octocounts.com/badge/Busnes-app/KyQuickStart-AI/branch/master)](https://octocounts.com/github/Busnes-app/KyQuickStart-AI/tree/master)

## Documentation

- [Install targets](docs/TARGETS.md) — installing on this computer, connecting servers over SSH, and Kubernetes clusters. <a id="installing-on-this-computer"></a><a id="connecting-your-servers-over-ssh"></a><a id="kubernetes-clusters"></a>
- [Agent permissions](docs/AGENT-PERMISSIONS.md) — the agent's dedicated account, its rights, and hands-off mode. <a id="letting-the-agent-work-without-admin-rights"></a><a id="hands-off-mode"></a>
- [During and after a run](docs/RUNS.md) — the dashboard, secrets, the run folder's files, and what a run proves. <a id="while-it-works"></a><a id="secrets"></a><a id="what-you-get"></a><a id="verification-and-readiness"></a>
- [Strong SSH](docs/STRONG-SSH.md) — the SSH algorithm and key policy.
- [Strong Kubernetes TLS](docs/STRONG-KUBERNETES-TLS.md) — the opt-in strong TLS profile for Kubernetes.
- [Strong updates](docs/STRONG-UPDATES.md) — the security profile for downloading kyquickstart.
- [Verifying releases](docs/VERIFYING-RELEASES.md) — check a release tag against its source.
- [Assurance case](docs/ASSURANCE-CASE.md) — threat model, trust boundaries, and why the security requirements are met.
- [Contributing](CONTRIBUTING.md) — how to propose a change and what it must pass.
- [Security policy](SECURITY.md) — how to report a vulnerability privately.
- [Release notes](CHANGELOG.md) — what changed in each release, and its upgrade impact.
