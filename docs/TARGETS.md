# Install targets

[Product overview](../README.md)

Commands and unlinked file paths below are relative to the repository root.

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
2. Logs in **as you**, with `sudo`, once, and runs [`bin/prepare-host.sh`](../bin/prepare-host.sh)
   to create the agent's own login ([next section](AGENT-PERMISSIONS.md#letting-the-agent-work-without-admin-rights)).
3. Pins the server's host key. The server reports its key fingerprint over your own login, and
   the launcher refuses to continue if the network answers with a different one. A changed key
   is never accepted later either.
4. Adds `Host kyq-<name>` to `~/.ssh/kyquickstart-ai/config`, included from the top of
   `~/.ssh/config` (it asks first), so `ssh kyq-<name>` works for you and the agent.
5. Tests the agent's login and Docker access.

Each run starts its own ssh-agent holding only this key, for `kyquickstart`, and stops it
when the agent exits; your other keys never reach the run.

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

Product-owned SSH calls require RSA keys of at least 2048 bits, remove obsolete algorithms
from maintained OpenSSH defaults, and open a fresh transport rather than reuse an existing
control master. Existing strong identities and certificates can be retained. For a supported
configuration that also screens administrator certificate authorities, follow
[Strong SSH](STRONG-SSH.md). This policy covers launcher/helper calls; an agent's arbitrary
commands and its model-provider CLI are separate boundaries.

## Kubernetes clusters

For verified key floors on launcher-owned Kubernetes requests, select the
[strong Kubernetes TLS profile](STRONG-KUBERNETES-TLS.md). It requires a
supported kubectl build and separate review of local client credentials.

```sh
./kyqs-ai add-cluster <name> <admin-kubeconfig>       # target kube-<name>
./kyqs-ai revoke kube-<name> <admin-kubeconfig>       # delete the agent's ServiceAccount
./kyqs-ai remove-cluster <name>                       # stop offering it; the cluster is untouched
```

`add-cluster` needs `kubectl` and your admin kubeconfig (its current context, mode 0600). It
uses it once to create, in namespace `kyqs-ai`, a ServiceAccount `kyqs-ai-<name>` with a token
Secret and a ClusterRole and binding of the same name. The agent and `kyquickstart` get only
that ServiceAccount's kubeconfig, written to
`~/.local/state/kyquickstart-ai/clusters/kube-<name>` (mode 0600); your admin kubeconfig is not
recorded. The launcher refuses an admin kubeconfig that skips TLS verification. Re-running
`add-cluster` is safe and repairs a half-finished setup.

The ClusterRole holds exactly the permissions `kyquickstart preflight` checks (KyQuickStart's
`internal/kube/preflight.go`), plus `get` on `pods/log` for `logs`, all cluster-wide:
namespaces, pods, `pods/exec`, `pods/portforward`, Secrets, Services, PersistentVolumeClaims,
Deployments, NetworkPolicies, listing StorageClasses, and Leases (cluster-wide because
kyquickstart creates its lock namespace on the first apply). It cannot change RBAC, nodes or
ServiceAccounts, delete namespaces or volumes, or list Secrets.

**Be aware:** that is not cluster-admin, but it is close. Creating pods and reading Secrets in
every namespace lets a misbehaving agent run a pod as any ServiceAccount, or read any Secret
it can name, and so gain other accounts' rights. As with the docker group, the account is
dedicated and removed when you finish. `kyquickstart handoff` to KyYard on a Kubernetes target
creates RBAC objects, which this account cannot; the agent gives you that step.

`revoke kube-<name>` deletes the binding, the ClusterRole, the token and the ServiceAccount;
the API server stops accepting the token within seconds. Apps, their `kyq-<app>` namespaces
and the `kyqs-ai` namespace stay. `hosts` then lists the cluster as revoked, and `add-cluster`
gives the agent access again. `remove-cluster` warns if the ServiceAccount still exists.
A cluster added by an earlier version recorded your own kubeconfig; `hosts` reports it as not
ready until you run `add-cluster` again.

Claude Code's hands-off settings deny reading the agent's kubeconfig; for other agents the
prompt's ban is an instruction, not a barrier. Each app gets its own `kyq-<app>` namespace;
kyquickstart never adopts an object it did not label.
