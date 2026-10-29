# Assurance case

[Overview](../README.md) · [Verifying releases](VERIFYING-RELEASES.md) · [Contributing](../CONTRIBUTING.md)

This is the argument for what KyQuickStart AI protects and how. The tool hands a general-purpose
AI agent, which you choose and which talks to a model provider, a path onto your servers. Most of
what keeps that agent in bounds is an instruction in [PROMPT.md](../PROMPT.md), not a barrier, and
this page says plainly which is which. The binding contracts are in [AGENTS.md](../AGENTS.md)
(Local Contracts); the user-facing account is the [README](../README.md). Paths are relative to the
repository root; line numbers are for v0.5.0.

## What KyQuickStart AI must protect

1. **The agent gets no more than an unprivileged, revocable login.** On a server it is `kyops`:
   key-only, no password, no `sudo`. It is in the `docker` group, which is root-equivalent, and
   the docs say so. On a cluster it is the ServiceAccount `kyqs-ai-<name>`, bound to the
   permissions `kyquickstart preflight` checks; pod create and Secret get in every namespace
   can escalate, and the docs say so. Your own admin login, password and kubeconfig never
   reach it.
2. **It talks only to the servers you registered.** A host key is pinned once, after a check,
   and a changed key is refused.
3. **Secret values stay out of the agent's conversation**, and so out of your model provider's
   logs, *as far as the agent follows the prompt*. Mechanisms make that the easy path; nothing
   forces it (see Residual risk).
4. **Access ends when you say so.** `revoke` removes the agent's key and Docker access, or a
   cluster's ServiceAccount and its rights, and leaves apps and data alone.
5. **What runs is what was released.** The `kyquickstart` binary it installs must match
   GitHub's published digest and a build attestation from KyQuickStart's release workflow at
   that release's tag.

## Threat model

| Source | Can | Risk |
|---|---|---|
| The agent itself (a model mistake) | Run any command its mode allows, on any target | Delete data, misconfigure, print a secret |
| Text the agent reads: product READMEs, web pages, logs, issue text | Carry instructions (prompt injection) | Steer an agent with `ssh`, `curl` and `./bin/on` pre-approved |
| The model provider | Sees everything the agent reads and writes | Learn secrets that reach the conversation |
| Network attacker between this computer and a server | Answer as the server | Receive the agent's commands, impersonate a host |
| Someone with the run folder or handover sheet | Read files under `~/.local/state/kyquickstart-ai` | Administrator passwords, the plan |
| A tampered `kyquickstart` download or launcher update | Replace bytes on the way | Run their code with the agent's access |

Out of scope: a compromised workstation or user account (it already has your SSH keys and
kubeconfigs), and a server that is already compromised.

## Trust boundaries

1. **You → the server, once, as admin.** `add-host` logs in with your own account and `sudo` and
   runs `bin/prepare-host.sh` as root. The script travels base64-encoded, so your login shell
   cannot reinterpret it (`kyqs-ai` lines 183-189, `remote_root`). This is the only root-run
   code, with `bin/revoke-host.sh`.
2. **The agent → servers, as `kyops`.** Through `ssh kyq-<name>` with the KyQuickStart AI key
   only (`IdentitiesOnly`), its own `known_hosts` and `StrictHostKeyChecking yes` (lines 66-76).
   `kyops`' key line carries `restrict` (no forwarding, no terminal) and the account is locked to
   key-only use (`bin/prepare-host.sh`).
   Product-owned calls pass through `bin/ssh-policy`, including diagnostics, admin bootstrap,
   revoke, `bin/on` and handover. It requires RSA-2048 endpoint keys, removes obsolete
   negotiation mechanisms from maintained defaults and bypasses existing control masters.
   New runs copy that helper. A reviewed `KYQS_SSH_CONFIG` profile additionally isolates
   administrator identities and trusted CAs; see [Strong SSH](STRONG-SSH.md). OpenSSH's RSA
   floor does not inspect signing CAs, and the default general operator configuration is
   not an automatic CA audit. Direct arbitrary agent commands keep the authority below.
3. **`kyquickstart` → servers and clusters.** Each run gets its own ssh-agent holding only the
   KyQuickStart AI key, stopped on exit (lines 336-343). Kubeconfigs are passed by path. The
   one in `targets.tsv` is the ServiceAccount's that `add-cluster` wrote (0600, `kube_grant`,
   `add_cluster`); your admin kubeconfig is used once to create it, must be private, and is
   not recorded.
4. **The agent ↔ this computer.** In `local` mode the agent runs as you. The only separation is the
   agent CLI's own permission mode: supervised (asks per command) or hands-off (below).
5. **The agent → secrets.** Secrets live in 0600 files on targets; you add yours with `put-secret`,
   and `bin/handover` resolves them into a 0600 sheet after the agent exits.

## Hands-off mode: what the allow-list does and does not do

For Claude Code the launcher writes `.claude/settings.json` in the run folder (lines 356-369):
allowed are `ssh`, `scp`, `curl`, `dig`, `getent`, `git clone`/`-C`/`ls-remote`, the run's
helpers (`./bin/on`, `./bin/progress`, `./bin/redact`, `./bin/handover`, `./bin/kyquickstart`)
with any arguments, and the Read, Edit and Write tools with no path limit. The one deny is `Read`
on each registered kubeconfig. For Codex, `-a never` inside its `workspace-write` sandbox with
network on (lines 373-378). Gemini CLI and opencode get no hands-off mode.

The allow-list removes prompts for the commands an install needs. **It is not a sandbox**:

- `./bin/on local '<cmd>'` runs any command on this computer as you, and `./bin/on kyq-<name>`
  any command on a server (`bin/on`).
- The kubeconfig deny covers the Read tool only. `curl file://…`, `./bin/on local cat …` and
  `scp` to a server are allowed and reach the same file. The deny stops an accidental read, not a
  determined one.
- `./bin/handover` is allowed and the Read tool is unrestricted, so an agent that ran it and then
  read `handover.txt` would see every password. The prompt tells it never to open the result.
- `ssh`, `scp` and `curl` are allowed for any host, so data can leave over the network.

[Agent permissions](AGENT-PERMISSIONS.md) says this ("These rules are not limited to your `kyq-*` servers", "an instruction, not
an enforcement"); supervised mode is the choice for anyone who wants to approve each command.

## Secure design principles applied

- **Least privilege.** A dedicated, key-only, sudo-less account per server instead of your admin
  login; a dedicated SSH key; a per-run ssh-agent with that key alone.
- **Fail-safe defaults.** Supervised mode unless you choose hands-off. A host whose reported key
  differs from the network's, or whose pinned key changed, is refused (`add_host`). A target
  that is not ready is skipped and named. A kyquickstart download that fails its digest or
  attestation is deleted, not installed (`kyq_update`).
- **Economy of mechanism.** One helper (`bin/on`) for every target command; one script each to
  grant and revoke server access.
- **Separation of privilege.** Root actions run once, through your own login and `sudo`, never by
  the agent; anything else needing root is handed to you as a command.
- **Psychological acceptability.** The docker-group equivalence, the hands-off scope and every
  "instruction, not barrier" are printed at the point of choice (lines 433-441) and in [Agent permissions](AGENT-PERMISSIONS.md).

## Common weaknesses and how they are countered

| Weakness | Counter | Where |
|---|---|---|
| Command injection through names and addresses | `add-host` accepts only `[a-z0-9-]` names, `[A-Za-z0-9.:-]` addresses, numeric ports and `[A-Za-z0-9._-]` logins; kubeconfig paths only `[A-Za-z0-9._/-]` | `kyqs-ai` lines 197-200, 266 |
| Shell reinterpretation on the server | Root scripts sent base64 and decoded by `sh`; the key argument is base64 too | `kyqs-ai` `remote_root`, `bin/prepare-host.sh` |
| Man-in-the-middle at first contact | The server reports its ed25519 fingerprint over your own admin login; a different network answer stops `add-host`; `--prepared` makes you compare it by hand | `kyqs-ai` lines 218-236, `test/e2e.sh` |
| Changed host key later | A different key for a pinned alias is never accepted; ssh runs with `StrictHostKeyChecking yes` | `kyqs-ai` lines 237-242, `test/e2e.sh` ("a changed host key is refused") |
| Path traversal when storing or reading secrets | `put-secret` requires a path under `/srv/ky/` of `[A-Za-z0-9._/-]` with no `..`; `bin/handover` refuses unsafe hosts and paths | `kyqs-ai` `put_secret`, `bin/handover` `fetch`, both tests |
| Secrets in files others can read | `umask 077` for the run folder, secrets and the handover; kubeconfigs must be private | `kyqs-ai` line 582, `bin/handover`, `put_secret` |
| Secrets in logs the agent reads | `bin/redact` masks password/secret/token/key assignments, bearer and basic credentials and six-digit codes on lines that mention a pairing code; a backstop, not a guarantee | `bin/redact`, `test/unit.sh` |
| Tampered or replayed `kyquickstart` download | `gh` only, under `GODEBUG=fips140=on`; SHA-256 against GitHub's published asset digest; `gh attestation verify --deny-self-hosted-runners --cert-identity …/release-image.yml@refs/tags/v<tag>` | `kyqs-ai` `kyq_update`, `test/unit.sh` |
| Lingering access | `revoke` empties `authorized_keys`, removes `docker` group membership and expires the account; `revoke kube-<name>` deletes the ServiceAccount, its token and its ClusterRole and binding | `bin/revoke-host.sh`, `revoke_cluster`, `test/e2e.sh`, `test/kube.sh` |
| Cluster-admin handed to the agent | The agent's kubeconfig is a ServiceAccount with the preflight list and `pods/log`; denied RBAC, nodes, ServiceAccounts, namespace and volume delete, Secret list | `kube_grant`, `test/kube.sh` |
| Custom kubectl crypto backend differs from upstream Go | Metadata and a successful startup probe do not establish vendor key-floor semantics; only the named clients are qualified. Run the full native TLS matrix before selecting a custom client, even when its OpenSSL FIPS provider is available | `docs/STRONG-KUBERNETES-TLS.md`, `test/kube-tls.sh` |

## Residual risk

- **Prompt rules are not enforced.** "Ask before anything destructive", "never open a
  kubeconfig", "never print a secret" and "stay on your targets" are instructions. A wrong or
  manipulated agent in hands-off mode can break each of them (above). Supervised mode is the
  control.
- **Prompt injection.** The agent reads third-party READMEs and web pages and then runs commands.
  Nothing filters that text.
- **Docker group = root** on every server where `kyops` exists, until `revoke`.
- **The cluster ServiceAccount can escalate.** Creating pods and reading Secrets in every
  namespace lets it act as other ServiceAccounts, until `revoke kube-<name>`.
- **Launcher updates are not signature-checked**: `self_update` fast-forwards from the upstream
  over HTTPS ([VERIFYING-RELEASES.md](VERIFYING-RELEASES.md) shows the manual check).
- **The handover sheet is plaintext** administrator credentials until you shred it.
- **No independent security audit** has been done.

## Evidence

- **Static analysis:** `shellcheck -x kyqs-ai bin/* test/*.sh` in CI's `linux` job (the check the
  ruleset requires); `bash -n` and `./kyqs-ai help` on macOS (bash 3.2, BSD tools).
- **Tests:** `test/unit.sh` (Linux and macOS): progress, dashboard, redaction, handover
  (traversal refused, 0600), `bin/on`, the setup form. `test/e2e.sh` (Linux, Docker): a
  disposable sshd container for add-host, pinning, tamper refusal, `--prepared`, put-secret,
  clusters, a guided start with a stub agent (allow-list and denied kubeconfig), local mode,
  revoke and re-add. They use stub Docker, agent, `kubectl` and `kyquickstart` commands.
  `test/kube.sh` (CI's `kube` job, kind) checks the cluster ServiceAccount's allowed and denied
  rights, re-runs, revoke, and a real `kyquickstart preflight`. `test/unit.sh` checks
  `kyq_update` with a stub `gh`: FIPS policy, digest, tag-pinned attestation, no curl fallback
  and release ordering. `self_update` has no tests.
- **Review:** the `main: green checks` ruleset requires a pull request into `master` with the
  `linux` check green; repository administrators can bypass it.

This case is updated when a trust boundary, the allow-list or a security requirement changes. A
pull request that moves one must update this page in the same change.

## Selected Kubernetes TLS profile

Launcher `kubectl` calls share `bin/kubectl-policy`. With
`KYQS_STRONG_KUBE_TLS=1`, a supported standard Go client must retain normal peer
verification and apply the Go TLS key/algorithm policy. Admission checks release
metadata and probes the actual client under the selected crypto mode. In the
strong profile the helper locally refuses insecure/non-HTTPS kubeconfigs before requests, including
revocation; both launcher admin operations also require verified HTTPS in
compatibility mode and fail closed if inspection fails. It does not rely on a
false flag overriding a true kubeconfig boolean. Native regressions check weak leaf/intermediate/root refusal before administrative HTTP, strong controls
and ordinary trust failures, including zero TCP/HTTP for insecure kubeconfigs
through the helper, onboarding and revocation. The real-cluster suite checks grants,
repair and revocation in this profile. Local client credentials and external
credential providers require operator review; [the profile guide](STRONG-KUBERNETES-TLS.md)
owns compatibility, build admission and independent-transport limits.
