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
profile the helper requires a standard Go1.24-or-later Go1.x release build,
appends `fips140=on` to that child process's GODEBUG, and forces peer verification.
Other Go settings remain; an explicitly selected `fips140=only` remains stricter.
Unsupported/unidentifiable builds, invalid selector values and caller verification
bypasses fail before a Kubernetes request. An insecure kubeconfig cannot override
the helper's verification flag. The existing add-cluster check still refuses
kubeconfigs that explicitly skip verification.

Go's TLS policy checks the normally verified peer certificate chain, including its
trust anchor, against its allowed keys and algorithms. The qualified native clients
refuse literal RSA1024 and2047 at leaf/intermediate/root positions before HTTP,
retain RSA2048/P256 controls, and still reject wrong-host, untrusted and expired
certificates. Keep existing strong private CAs, certificate names and credentials;
normal trust and hostname verification remain enabled. This profile does not
rewrite a kubeconfig, rotate keys or change the granted ServiceAccount rights.

## Operator credential review

Peer-chain filtering is separate from the local credentials a kubeconfig selects.
Use strong existing bearer credentials or client certificates. For mTLS, inspect
the selected public certificate/key and its issuer chain: RSA at least2048 actual
bits or supported NIST curves at least256bits. Keep the private signer in its
current location. Review renewed certificates before use; do not assume this Go
setting checks the size of every locally imported client key. Exec credential
providers and HTTPS proxies need their own reviewed transport/credential policy.
No unreviewed alternative credential source belongs in this selected configuration.

## Scope and compatibility

Unset or `KYQS_STRONG_KUBE_TLS=0` retains existing compatibility behavior, including
acceptance of otherwise trusted short-RSA TLS peers. Select the strong profile when
using this documented configuration. A peer relying on excluded key sizes or
algorithms needs a server-side upgrade or a different strong certificate. Test
access before onboarding or revoking with the selected profile.

This setting covers launcher-owned `kubectl` calls only. SSH, Git/curl/gh updates,
model-provider CLIs, arbitrary agent commands and the separate KyQuickStart binary
have independent transports. Apply their documented profiles separately. This
bounded configuration does not establish whole-project OpenSSF compliance.

## Verification

`test/kube-tls.sh` uses an actual native client against disposable loopback TLS
servers and observes TCP and administrative HTTP separately. It exercises both
the helper and actual `add-cluster`; no fixture exposes a writable Kubernetes API.
`test/kube.sh` separately proves real ServiceAccount/RBAC creation, access, repair,
revocation and re-add against a disposable cluster; CI selects the strong profile.

The native Linux/amd64 matrix is qualified with kubectl1.35.0/Go1.25.5 and
kubectl1.37.0/Go1.26.6. macOS unit checks qualify shell portability, not a native
macOS TLS handshake. Standard Go1.24 source documents the runtime switch and
literal RSA chain checks; version metadata is an admission check, not a substitute
for running the matrix on custom builds.

Sources:
- https://go.dev/doc/go1.24#fips140
- https://github.com/golang/go/blob/go1.24.0/src/crypto/tls/internal/fips140tls/fipstls.go
- https://github.com/golang/go/blob/go1.24.0/src/crypto/tls/common.go#L1698
