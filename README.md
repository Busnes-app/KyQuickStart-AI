# KyQuickStart AI

Install the Ky suite with the AI coding agent you already use. `kyqs-ai` connects your
servers over SSH, starts the agent with an installation prompt, shows a live status board
while it works, and gives you a printable sheet of URLs, logins and passwords at the end.

The prompt directs the agent to install the selected Ky apps, create separate
**administrator** and **everyday** users, configure selected identity/backup/monitoring
integrations, and report the outcome. Completion depends on product readiness, supplied
services and observed checks; launching an agent does not guarantee these steps succeeded.
It follows each product’s README and records missing or incorrect instructions.

**Status:** first test. Expect the agent to hit README gaps; that is what the report is for.
No third-party app has completed suite admission yet, so the agent labels each one a test
install. For the deterministic installer, see [KyQuickStart](https://github.com/Busnes-app/KyQuickStart).

## What you need

- **Your computer:** Linux or macOS with `bash`, `ssh`, `git`, and one supported agent CLI:
  [Claude Code](https://docs.claude.com/en/docs/claude-code) (`claude`),
  [Codex CLI](https://github.com/openai/codex) (`codex`),
  [Gemini CLI](https://github.com/google-gemini/gemini-cli) (`gemini`) or
  [opencode](https://opencode.ai) (`opencode`). `tmux` is optional; it puts the dashboard beside the agent.
- **Where the apps run:** this computer, servers, or both. Each needs Linux with Docker Engine
  and the compose plugin already installed (Podman is not supported). Servers need a login that can use `sudo` (once,
  below). x86-64 is what the suite targets.
- **A domain you control.** The apps need HTTPS hostnames (passkeys and sign-in require it).
  LAN-only is fine; public DNS records may point at private addresses.

## Start

```sh
git clone https://github.com/Busnes-app/KyQuickStart-AI.git
cd KyQuickStart-AI
tmux new -s ky        # optional: dashboard opens in a side pane
./kyqs-ai
```

The launcher walks you through:

1. **Where to install.** This computer, one or more servers, or both. For each server give a
   short name, its address and your admin login.
2. **Agent.** It picks from the agents installed on your computer, and for Claude Code and Codex
   asks whether to run hands-off (below).
3. **The run.** The agent interviews you once (domain, apps, user names, proxy), checks the
   servers, and shows a plan. After you say "go" it works on its own, and only comes back for
   steps a person must do, batched together.
4. **Handover.** When you exit the agent, the launcher builds the handover sheet and offers to
   show and print it.

Continue an interrupted run with `./kyqs-ai resume`. See all commands with `./kyqs-ai help`.

## Installing on this computer

Answer yes to "Install on this computer?" (or run `./kyqs-ai add-local`). No SSH is involved:

- You need Docker access yourself (`docker info` works without `sudo`).
- Apps go under `/srv/ky`, owned by you. If it doesn't exist, the launcher asks to run
  `sudo install -d -m 750 -o $USER -g $USER /srv/ky` once.
- The agent runs commands **as you**, with your rights, not as a separate login. The prompt
  confines it to `/srv/ky`, the run folder and the containers it creates, and forbids `sudo`.
  That is an instruction, not a barrier; choose supervised mode to approve each command.
- Apps stop when the computer sleeps or shuts down, and other devices reach it at its LAN
  address, so give it a fixed one. Good for trying the suite; use a server to keep it.

`./kyqs-ai revoke local` stops offering this computer as a target; it removes nothing.

## Connecting your servers over SSH

`./kyqs-ai add-host <name> <address> [port] [admin-user]` (also offered by the guided start):

1. Creates a dedicated key, `~/.ssh/kyquickstart-ai/id_ed25519`. A passphrase is recommended;
   the launcher loads it into `ssh-agent` for 12 hours.
2. Logs in **as you**, with `sudo`, once, and runs [`bin/prepare-host.sh`](bin/prepare-host.sh)
   to create the agent's own login (next section).
3. Pins the server's host key. The server reports its key fingerprint over your own login, and
   the launcher refuses to continue if the network answers with a different one. A changed key
   is never accepted later either.
4. Adds `Host kyq-<name>` to `~/.ssh/kyquickstart-ai/config`, included from the top of
   `~/.ssh/config` (it asks first), so `ssh kyq-<name>` works for you and the agent.
5. Tests the agent's login and Docker access.

It is safe to repeat. If any step fails, the server is not registered, and the guided start
skips (and names) any target that is not ready. `./kyqs-ai hosts` shows what is wrong with
each one. An address that is this computer is refused; use `add-local` for that. To do step 2 by hand at the server console instead:

```sh
# on your computer: print the agent's key as one base64 line (creates the key if needed)
./kyqs-ai ssh-key
# on the server, as root, with a copy of bin/prepare-host.sh; note the KYQ-HOSTKEY line
sh prepare-host.sh <the base64 line>
# back on your computer; it asks you to compare the fingerprint with KYQ-HOSTKEY
./kyqs-ai add-host --prepared <name> <address> [port]
```

## Letting the agent work without admin rights

The agent never gets root or your password. `prepare-host.sh` creates a user `kyops` that:

- logs in only with the KyQuickStart AI key (`restrict`: no forwarding, no terminal),
- has no password and no `sudo`,
- belongs to the `docker` group, and owns `/srv/ky`, where every app is installed.

**Be aware:** membership of the `docker` group is equivalent to root on that server. That is
unavoidable for a tool that installs containers. It is why the account is dedicated, key-only,
and removed when you finish:

```sh
./kyqs-ai revoke <name>     # removes kyops' key and docker access; apps and data stay
```

After that, `./kyqs-ai hosts` lists the server as revoked. `./kyqs-ai add-host` with the
same name and address gives the agent access again.

Anything that really needs root (firewall, packages) is given to you as a command to run yourself.

### Hands-off mode

By default your agent asks before each command. Hands-off mode pre-approves the commands
the install uses, so the agent stops when it needs you, not for every `ssh`:

| Agent | Hands-off pre-approves | Supervised |
|---|---|---|
| Claude Code | The launcher writes the run folder's `.claude/settings.json`, allowing any command starting with `ssh`, `scp`, `git clone`, `git -C`, `git ls-remote`, `curl`, `dig`, `getent`, `./bin/on`, `./bin/progress`, `./bin/redact` or `./bin/handover`, plus the Read, Edit and Write tools with no path limit | normal prompts |
| Codex | Runs `codex -s workspace-write -c sandbox_workspace_write.network_access=true -a never`: every command runs without asking, writes on this computer stay in the run folder (and `/srv/ky` when this computer is a target), network is on | same sandbox, `-a on-request` |
| Gemini CLI, opencode | not offered | normal prompts |

**These rules are not limited to your `kyq-*` servers.** `ssh`, `scp` and `curl` are approved
for any host and any arguments, and Codex's sandbox lets every command reach the network.
`./bin/on` runs whatever command it is given, on a `kyq-*` server or, with `local`, on this
computer as you. The prompt is what keeps the agent on your targets.

In both modes the prompt tells the agent to ask before anything destructive. That is an
instruction, not an enforcement: a misbehaving agent with Docker access could still read or
delete anything on that server. Use supervised mode if you want to approve each command.

At the end the agent offers to file the Ky product problems it found as GitHub issues for
the Busnes.app team, with domains, addresses, names and secrets replaced by placeholders.
It shows you each issue and files only the ones you approve, using your `gh` login. `gh` is
not in the Claude Code hands-off list, so it still asks; Codex hands-off runs it unasked,
so the approval there is the prompt's instruction alone.

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

## Secrets

- The prompt has the agent generate secrets on the servers and move them by pipe, so the
  values stay out of its conversation and your AI provider. This is an instruction the agent
  follows, not a barrier: an agent that ignores it can read them. Logs it reads pass through
  a redaction filter as a backstop, and the prompt tells it to report any secret it sees.
- The handover sheet is assembled by [`bin/handover`](bin/handover) after the agent exits,
  reading each secret straight from its server into a file only you can read (mode 0600).
  Save the logins in a password manager, then `shred -u` the file.
- The run folder is `~/.local/state/kyquickstart-ai/runs/<time>/` (mode 0700).

## What you get

| File in the run folder | Contents |
|---|---|
| `handover.txt` | URLs, administrator and everyday logins, break-glass admins, remaining manual steps |
| `feedback.md` | Test report: what worked, what failed, and the README changes each repo needs |
| `install-guide-draft.md` | The install sequence that worked, written for a newcomer |
| `state.md` | The plan, decisions and everything created, for resuming and auditing |
| `progress.log` | The dashboard's event log |

## Verification and readiness

The launcher tests check launcher behavior, secret redaction, host-key handling and
handover mechanics. The end-to-end harness uses disposable SSH infrastructure and a stub
Docker command/agent; it is **not a full Ky-product install or recovery test**.

Read each run’s `feedback.md`, `state.md` and handover before using the installation.
Require separate observed evidence for email send/receive and verification links, real
MFA approval, product access/offboarding, backup deposits, blob/bulk coverage, custodian
card distribution and a scratch restore with the actual cards. A generated handover,
screenshot, successful health response or synthetic recovery drill proves only its own
scope. Keep passwords and real recovery shares out of public reports and promo images.

## Development

```sh
shellcheck kyqs-ai bin/* test/*.sh
test/unit.sh      # progress, dashboard, redact, handover
test/e2e.sh       # needs Docker: add-host, key pinning, put-secret, handover, revoke
```

## License

MIT. See [LICENSE.txt](LICENSE.txt).
