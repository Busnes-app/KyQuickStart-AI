# Verifying releases

[Overview](../README.md) · [Changelog](../CHANGELOG.md) · [Assurance case](ASSURANCE-CASE.md)

KyQuickStart AI is released as source only. A release is the git tag `vX.Y.Z` on `master` and
the GitHub release of the same name; there is no binary, image or archive to download, and you
run a clone ([CHANGELOG.md](../CHANGELOG.md)). So verifying a release means checking that your
clone is at the commit the tag names, and that GitHub signed that commit.

## What is signed, and by whom

- Every release tag so far points at the merge commit of the release pull request. GitHub
  creates that commit when the pull request is merged and signs it with its web-flow key
  (`B5690EEEBB952194`, "GitHub <noreply@github.com>", published at
  <https://github.com/web-flow.gpg>). The signature covers the commit's tree, so every file of
  the release.
- The signature says the commit was made on GitHub through a merged pull request, which the
  `main: green checks` ruleset gates on the `linux` CI job. It is GitHub's signature, not the
  maintainer's own.
- **The tag itself is not signed** (a lightweight tag), and no ruleset protects tags. Record the
  commit a release names when you first fetch it, and treat a tag that later names another
  commit as a warning.
- The commits inside a pull request are not signed; only the merge commits are.

## Verify a release

```sh
v=<release version, e.g. 0.5.0>
git clone https://github.com/Busnes-app/KyQuickStart-AI.git && cd KyQuickStart-AI
git checkout -q "v$v"
gh api "repos/Busnes-app/KyQuickStart-AI/commits/v$v" --jq '"\(.sha) verified=\(.commit.verification.verified)"'
git rev-parse HEAD
```

The two hashes must be equal and GitHub must say `verified=true`. To check the signature
yourself instead of trusting GitHub's API, import GitHub's key into a keyring of its own and
let git verify it:

```sh
export GNUPGHOME=$(mktemp -d)
curl -fsSL https://github.com/web-flow.gpg | gpg --quiet --import
git verify-commit "v$v"    # Good signature from "GitHub <noreply@github.com>", key B5690EEEBB952194
```

gpg also warns that the key is not certified by a key you trust; that is expected, because
you fetched it from github.com over HTTPS rather than meeting GitHub's key holder.

Both commands were run against v0.5.0 (commit `7dc55aa`): GitHub reports `verified=true`, and
`git verify-commit` gives a good signature from key `B5690EEEBB952194`.

## Updates inside the launcher

At `start` and `resume`, `kyqs-ai` offers to fast-forward your clone to its upstream branch
(`self_update`). That trusts GitHub over HTTPS and does not check signatures. After an update
you can check the new `HEAD` the same way: `git verify-commit HEAD`, and on `master` compare it
with the newest tag (`git describe --tags`).

The `kyquickstart` binary the launcher offers to download is a KyQuickStart release; it is
checked against GitHub's published SHA-256 digest and its build attestation from
`release-image.yml` at that release's tag ([STRONG-UPDATES.md](STRONG-UPDATES.md)). KyQuickStart's
[docs/VERIFYING-RELEASES.md](https://github.com/Busnes-app/KyQuickStart/blob/master/docs/VERIFYING-RELEASES.md)
shows how to check it yourself, pinned to the release workflow and tag.

## Rebuild

There is nothing to rebuild: the release is the source you run.
