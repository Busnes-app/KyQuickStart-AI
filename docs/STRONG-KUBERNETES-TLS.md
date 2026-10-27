# Strong Kubernetes TLS configuration

Set `KYQS_STRONG_KUBE_TLS=1` for the launcher's Kubernetes onboarding and revocation:

```sh
export KYQS_STRONG_KUBE_TLS=1
kubectl version --client -o json
./kyqs-ai add-cluster lab /private/admin-kubeconfig
# Later, with the same setting:
./kyqs-ai revoke kube-lab /private/admin-kubeconfig
```

Every fixed launcher `kubectl` call goes through `bin/kubectl-policy`. In this
profile the helper requires Go 1.24-or-later Go 1.x release metadata,
selects `fips140=on` in that child process's GODEBUG, and requires a verified
HTTPS kubeconfig. The local `version --client -o json` metadata probe must also succeed under
that exact environment before a request; release metadata alone cannot identify
a vendor crypto backend or prove its runtime is usable. Startup failures include
the actual runtime diagnostic; inherited unsupported Go settings may be the cause.
Other Go settings remain; an explicitly selected `fips140=only` remains stricter.
Unsupported/unidentifiable builds, invalid selector values and caller verification
bypasses fail before a Kubernetes request. Every fixed helper call names one
kubeconfig first and permits no target, trust-anchor, TLS-name or credential
overrides. The helper inspects
that selected cluster before onboarding or revocation and refuses plain HTTP or
`insecure-skip-tls-verify: true`. client-go does not reliably merge a false CLI
boolean over a true kubeconfig setting, so the flag alone cannot enforce this.

Go's TLS policy checks the normally verified peer certificate chain, including its
trust anchor, against its allowed keys and algorithms. The qualified native clients
refuse literal RSA-1024 and RSA-2047 at leaf/intermediate/root positions before HTTP,
retain RSA-2048/P-256 controls, and still reject wrong-host, untrusted and expired
certificates. Keep existing strong private CAs, certificate names and credentials;
normal trust and hostname verification remain enabled. This profile does not
rewrite a kubeconfig, rotate keys or change the granted ServiceAccount rights.

## Operator credential review

Peer-chain filtering is separate from the local credentials a kubeconfig selects.
Use strong existing bearer credentials or client certificates. For mTLS, inspect
the selected public certificate/key and its issuer chain: RSA at least 2048 actual
bits or supported NIST curves at least 256 bits. Keep the private signer in its
current location. Review renewed certificates before use; do not assume this Go
setting checks the size of every locally imported client key. Exec credential
providers and HTTPS proxies need their own reviewed transport/credential policy.
No unreviewed alternative credential source belongs in this selected configuration.

## Scope and compatibility

Unset or `KYQS_STRONG_KUBE_TLS=0` retains acceptance of otherwise trusted
short-RSA TLS peers. Onboarding and revocation require a verified HTTPS admin
kubeconfig in both modes and stop if local inspection fails. Select the strong profile when
using this documented configuration. A peer relying on excluded key sizes or
algorithms needs a server-side upgrade or a different strong certificate. Test
access before onboarding or revoking with the selected profile.

This setting covers launcher-owned `kubectl` calls only. SSH, Git/curl/gh updates,
model-provider CLIs, arbitrary agent commands and the separate KyQuickStart binary
have independent transports. Apply their documented profiles separately. This
bounded configuration does not establish whole-project OpenSSF compliance.

## Verification

`test/kube-tls.sh` uses an actual native client against disposable loopback TLS
servers and observes TCP and administrative HTTP separately. It exercises the
helper, actual `add-cluster`, and revocation with an insecure kubeconfig and an
untrusted peer. The strong profile refuses the insecure configuration before TCP
or HTTP; onboarding and revocation also refuse it in compatibility mode. Plain
HTTP and failed configuration inspection are separate refusal cases. The helper
compatibility control reaches only the owned peer with a public disposable token.
No fixture exposes a writable Kubernetes API.
`test/kube.sh` separately proves real ServiceAccount/RBAC creation, access, repair,
revocation and re-add against a disposable cluster; CI selects the strong profile.

The native Linux/amd64 matrix is qualified with kubectl 1.35.0/Go 1.25.5 and
kubectl 1.37.0/Go 1.26.6. macOS unit checks qualify shell portability, not a native
macOS TLS handshake. Standard Go 1.24 source documents the runtime switch and
literal RSA chain checks; version metadata is an admission check, not a substitute
for running the matrix on custom builds.
CI's real-cluster job extracts the qualified kubectl 1.35.0 from its pinned kind
node image instead of using the runner's vendor-modified Go/OpenSSL client,
whose FIPS provider may be unavailable. No TLS fallback is selected on failure. A second digest-pinned Microsoft
Go/OpenSSL client reproduces unavailable-provider rejection with real release
metadata; the wrapper must print its local refusal without TCP or HTTP.
This is a runtime availability check, not proof that every vendor build applies
upstream Go TLS restrictions. Qualify custom clients with the full native matrix.

Sources:
- https://go.dev/doc/go1.24#fips140
- https://github.com/golang/go/blob/go1.24.0/src/crypto/tls/internal/fips140tls/fipstls.go
- https://github.com/golang/go/blob/go1.24.0/src/crypto/tls/common.go#L1698
