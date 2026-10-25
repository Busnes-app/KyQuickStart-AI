# Security Policy

KyQuickStart AI drives installation through a local AI agent that plans and converses, using KyQuickStart as its deterministic execution layer. The execution layer, not the agent, enforces validated operations, ownership, credentials, and verifiable results.

## Reporting vulnerabilities

Report security vulnerabilities privately through GitHub Security Advisories:
<https://github.com/Busnes-app/KyQuickStart-AI/security/advisories>. Do not open a public issue.
Include the affected area, reproduction steps, impact, and affected versions.
We aim to acknowledge reports within two business days and will coordinate a fix
and disclosure.

## Trust boundaries and limitations

- The AI agent is untrusted for authority. Every operation that touches a server, credential, or secret runs through KyQuickStart's validated layer, which is the authorization boundary.
- Operator secrets — SSH keys, tokens, generated passwords — are the deterministic layer's to handle. They must not be logged, echoed into the agent transcript, or sent to any model or third party the operator did not configure.
- It connects only to operator-provided Docker hosts (over SSH) and Kubernetes clusters, bring-your-own; it never installs Docker or Kubernetes.

## Operating requirements

- Connect to targets over authenticated SSH/HTTPS; refuse redirects and unverified hosts.
- Expansion is frozen to compatibility, safety, verification, and the AI integration (see the catalog redirect note). New catalog apps and orchestration features are out of scope.
- Verify each result before reporting success; a hopeful exit code is not evidence.

## Security-sensitive changes

Changes to credential handling, SSH onboarding, the agent/execution boundary, or anything that lets agent output reach a server without validation require tests for both the expected path and the relevant
failure or attack path, plus a description of the trust boundary in the pull
request.

## Related documents

- [CONTRIBUTING.md](CONTRIBUTING.md) — contribution and review requirements
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) — community expectations
- [README.md](README.md) — what this project is and how to run it

