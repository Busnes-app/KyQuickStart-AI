# Native Kubernetes TLS fixtures

## Purpose

Prove the selected kubectl TLS policy before administrative HTTP requests leave the launcher.

## Ownership

Standard-library Go test fixtures, generated certificates and actual native-client probes.

## Local Contracts

- Generate only disposable CA/peer material; bind owned loopback listeners.
- Observe both TCP acceptance and HTTP requests with the public fixture token.
- Exercise helper and actual add-cluster paths, with strong and ordinary trust-failure controls.
- The fixture serves no writable Kubernetes API. `test/kube.sh` owns actual RBAC/ServiceAccount lifecycle proof.
- Keep normal host verification, race detection and complete native case selection.

## Verification

Run `test/kube-tls.sh` from the repository root. `KYQS_TEST_KUBECTL` can select an existing
standard native client; otherwise the script extracts the digest-pinned Linux client.

## Child DOX Index

None.
