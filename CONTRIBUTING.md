# Contributing

[Overview](README.md) · [Assurance case](docs/ASSURANCE-CASE.md) · [Verifying releases](docs/VERIFYING-RELEASES.md)

## Reporting

- **Bugs, run findings and requests:** open a GitHub issue. Attach the relevant part of the run's
  `feedback.md` or `progress.log`, with domains, addresses and names replaced by placeholders.
  Never attach `handover.txt` or anything from `/srv/ky/*/secrets`.
- **Vulnerabilities:** report privately, not in an issue. The
  [Busnes-app security policy](https://github.com/Busnes-app/.github/blob/main/SECURITY.md)
  covers this repository and gives the response times.

## Changing the code

1. Read [AGENTS.md](AGENTS.md). It is the binding contract for this repository; a change to a
   contract, the allow-list or a durable workflow updates it in the same pull request, and a
   change to a trust boundary updates [docs/ASSURANCE-CASE.md](docs/ASSURANCE-CASE.md).
2. Open a pull request against `master`. The `main: green checks` ruleset requires one, with the
   `linux` CI job green. The `macos` job runs too; keep both green.
3. Run the checks below before you push. `test/e2e.sh` needs Docker; CI runs it.
4. To release, add the `CHANGELOG.md` section, merge, and publish the GitHub release `vX.Y.Z` on
   `master` ([AGENTS.md](AGENTS.md), Ownership).

### Tests

New behaviour and every bug fix come with a test in `test/unit.sh` or `test/e2e.sh` that fails
without the change. A security-relevant path (host keys, secret paths, access, downloads) gets a
test of the refusal, not only of the success.

### Coding standard

Contributions follow these rules. CI enforces the parts a tool can check, so a failure is a red
build, not a review comment.

| Code | Standard | Enforced by |
|---|---|---|
| `kyqs-ai`, `bin/*`, `test/*.sh` | Clean under [ShellCheck](https://www.shellcheck.net/) with `-x`; a `# shellcheck disable=` names its reason on the same line | `shellcheck -x kyqs-ai bin/* test/*.sh` in the `linux` job |
| `kyqs-ai` and the bash helpers | bash 3.2 compatible (macOS): no associative arrays, negative indexes or `mapfile`; BSD and GNU tools both | `macos` job: `test/unit.sh`, `bash -n kyqs-ai` and `./kyqs-ai help` |
| `bin/prepare-host.sh`, `bin/revoke-host.sh` (run as root) | POSIX `sh`, `set -eu` | shellcheck reads their `#!/bin/sh` and checks them as POSIX sh |
| Commands sent through someone's login shell | base64 only, so fish, zsh or bash cannot reinterpret them | Review; `test/e2e.sh` runs `add-host` and `revoke` through them |

Beyond what the tools check: validate every value at the edge (names, addresses, paths) with an
allow-list regex as `kyqs-ai` does, quote every expansion, and keep to the comment density and
naming of the file you are editing.
