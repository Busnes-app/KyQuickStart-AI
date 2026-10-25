# Contributing to KyQuickStart AI

KyQuickStart AI is the prompt-driven installer: a local AI agent plans, converses, and diagnoses while KyQuickStart performs the validated, deterministic operations. Contributions must keep the AI agent out of the trust path — it proposes, but never holds final authority, credentials, or unvalidated execution.

## Before contributing

Read [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) and [SECURITY.md](SECURITY.md),
the [README](README.md), and any AGENTS.md in the subtree you are about to
touch. Open an issue before proposing a feature larger than a bug fix or
documentation change.

Keep changes small, reuse existing code, and fix the shared root cause rather
than the reported symptom. New non-trivial logic ships with a runnable test or
self-check.

## Security requirements

- The AI agent proposes; KyQuickStart validates and executes. Never let agent output bypass KyQuickStart's validation, ownership, or credential handling.
- SSH keys, tokens, and generated secrets are handled by the deterministic layer; the agent transcript must not capture, log, or transmit them.
- Treat model prompts and responses as untrusted input; validate before acting.
- It never installs Docker or Kubernetes and connects only to operator-provided targets.
- Do not add telemetry, phone-home, analytics, or unconfigured third-party
  services.
- Do not add silent security fallbacks; fail closed with a readable error and a
  remediation step.
- Name and document any security trade-off in [SECURITY.md](SECURITY.md) before
  it merges.

## Verification

Run the checks that apply to the files you changed, and the repository's
full required checks before hand-off. Record the exact commands and their
results in the pull request.

## AI attribution

AI-assisted contributions are welcome; undisclosed ones are not. Disclose
material AI assistance in the pull request — the tool, what it changed, and what
you personally ran, read, and verified — and add a commit trailer naming any
tool that materially contributed. You are the author of the code you submit for
every purpose, regardless of how it was produced.

## Pull requests

Branch off `main` with a focused name, and use a Conventional Commit subject
(`fix:`, `feat:`, `docs:`, `refactor:`, `test:`, or `chore:`). The pull request
explains why the change exists, the verification performed, the security impact,
and any known limitations.

Every pull request gets an adversarial review pass; see
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md#hostile-reviews-are-about-code-never-people)
for what that is and the boundary it keeps.

## Licence

KyQuickStart AI is licensed under the MIT License. See [LICENSE.txt](LICENSE.txt).

