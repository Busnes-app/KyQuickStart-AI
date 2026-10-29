# Agent permissions

[Product overview](../README.md)

Commands and unlinked file paths below are relative to the repository root.

## Letting the agent work without admin rights

The agent never gets root, your password or your cluster-admin kubeconfig (clusters: [above](TARGETS.md#kubernetes-clusters)).
On servers, `prepare-host.sh` creates a user `kyops` that:

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
| Claude Code | The launcher writes the run folder's `.claude/settings.json`, allowing any command starting with `ssh`, `scp`, `git clone`, `git -C`, `git ls-remote`, `curl`, `dig`, `getent`, `./bin/on`, `./bin/progress`, `./bin/redact`, `./bin/handover` or `./bin/kyquickstart`, plus the Read, Edit and Write tools with no path limit | normal prompts |
| Codex | Runs `codex -s workspace-write -c sandbox_workspace_write.network_access=true -a never`: every command runs without asking, writes on this computer stay in the run folder (and `/srv/ky` when this computer is a target), network is on | same sandbox, `-a on-request` |
| Gemini CLI, opencode | not offered | normal prompts |

Claude Code applies the run folder's settings only after you accept its "trust this folder"
dialog, which it shows once when the run starts; decline it and every command asks first.

**These rules are not limited to your `kyq-*` servers.** `ssh`, `scp` and `curl` are approved
for any host and any arguments, and Codex's sandbox lets every command reach the network.
`./bin/on` runs whatever command it is given, on a `kyq-*` server or, with `local`, on this
computer as you. `./bin/kyquickstart` includes `uninstall`, `unmanage`, `restore --replace`
and ownership take-over flags; kyquickstart itself keeps data on uninstall and refuses what it
does not own, but asking you first is the prompt's rule. The prompt is what keeps the agent on
your targets.

In both modes the prompt tells the agent to ask before anything destructive. That is an
instruction, not an enforcement: a misbehaving agent with Docker access could still read or
delete anything on that server. Use supervised mode if you want to approve each command.

At the end the agent offers to file the Ky product problems it found as GitHub issues for
the Busnes.app team, with domains, addresses, names and secrets replaced by placeholders.
It shows you each issue and files only the ones you approve, using your `gh` login. `gh` is
not in the Claude Code hands-off list, so it still asks; Codex hands-off runs it unasked,
so the approval there is the prompt's instruction alone.
