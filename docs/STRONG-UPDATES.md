# Strong kyquickstart updates

[Assurance case](ASSURANCE-CASE.md) · [Verifying releases](VERIFYING-RELEASES.md) · [SSH](STRONG-SSH.md) · [Kubernetes TLS](STRONG-KUBERNETES-TLS.md)

`kyqs-ai start` and `kyqs-ai upgrade` offer the latest `kyquickstart` release when the one in
use is older or missing (`kyq_update`). This page is the profile for that download.

The launcher first checks for updates. If this copy of KyQuickStart AI is behind its git
upstream, it offers to update it (`git pull --ff-only`) and restarts; a copy with local changes
is only reported. If `kyquickstart` is missing or older than the latest
[KyQuickStart release](https://github.com/Busnes-app/KyQuickStart/releases), it offers to
download the release binary for this computer. The download must match the SHA-256 digest
GitHub publishes for it and a build attestation from KyQuickStart's release workflow at that
exact tag; it replaces the old binary, or goes to `~/.local/bin`. A development build is only
reported. This needs the [GitHub CLI](https://cli.github.com/) `gh`, logged in; it runs under
Go's strong TLS policy ([Strong updates](#what-is-enforced)). Without it, install
`kyquickstart` yourself.

## What is enforced

- **`gh` only.** The release list, the binary and its attestation come through the GitHub CLI.
  Without `gh`, or when it is not logged in, the launcher says it could not check and keeps the
  binary it has. There is no curl fallback: curl's TLS key policy belongs to its build, not to
  this project.
- **Go's FIPS 140 TLS policy.** Every `gh` call runs with `GODEBUG=fips140=on` (an explicit
  `fips140=only` and other `GODEBUG` settings are kept). In a Go 1.24+ build this allows TLS 1.2+
  and certificate chains of RSA-2048+ or P-256+ keys only. This is not a FIPS certification claim.
- **Digest.** The download must match the SHA-256 digest GitHub publishes for that asset.
- **Tag-pinned attestation.** `gh attestation verify` must accept a Sigstore build attestation
  whose certificate identity is
  `https://github.com/Busnes-app/KyQuickStart/.github/workflows/release-image.yml@refs/tags/v<tag>`
  and whose runner was GitHub-hosted (`--deny-self-hosted-runners`). Authenticity rests on that
  signature, not on the TLS connection: a binary from another workflow, another ref, or an older
  release offered as new is refused.

Anything that fails is deleted and not installed; the binary in use stays.

## Check it yourself

```sh
gh release download v<tag> --repo Busnes-app/KyQuickStart --pattern 'kyquickstart-<tag>-linux-amd64'
GODEBUG=fips140=on gh attestation verify kyquickstart-<tag>-linux-amd64 \
  --repo Busnes-app/KyQuickStart --deny-self-hosted-runners \
  --cert-identity https://github.com/Busnes-app/KyQuickStart/.github/workflows/release-image.yml@refs/tags/v<tag>
```

`test/unit.sh` checks the launcher's behaviour with a stub `gh`, including that removing any
of these checks, or falling back to curl, fails.

## Out of scope

`gh`'s own build and Go version, the user's `gh` login, `self_update`'s `git fetch` of this
checkout (your clone's remote and Git configuration; see [VERIFYING-RELEASES.md](VERIFYING-RELEASES.md)),
model-provider CLIs and commands the agent runs. Those are stock tools with their own transport
settings.
