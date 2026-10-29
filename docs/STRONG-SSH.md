# Strong SSH configuration

The launcher, `bin/on` and `bin/handover` use `bin/ssh-policy`. It checks that the actual
client supports `RequiredRSASize` (OpenSSH 9.1+), requires RSA-2048 endpoint keys, removes
SHA-1 KEX/signatures, CBC/RC4 ciphers and SHA-1/MD5/64-/96-bit MACs from maintained defaults,
and uses `ControlPath none`. Maintained hybrid post-quantum KEX remains eligible. HMAC-SHA1
and truncated MAC tags are policy exclusions, not claims that they are SHA-1 signature attacks
or that a tag length is the cipher's key length. Non-RSA OpenSSH endpoint keys use Ed25519,
supported NIST P-256/P-384/P-521 curves or their supported hardware-backed variants.

Keys, server pins and encrypted application data are not rotated. Servers offering only
excluded mechanisms need a server-side upgrade before these helpers can connect. Local-only
runs do not use SSH. New runs retain their own helper copy; existing run folders retain their
previous helpers until `./kyqs-ai upgrade` copies this checkout's helpers into them (with a
newer `kyquickstart`). To update only the helpers, stop the run's agent, back up its `bin/`
directory, then copy this checkout's `bin/on`, `bin/handover` and `bin/ssh-policy` into it
together. Keep the run's `kyquickstart` binary and all state/data. Resume after checking access
with the updated `bin/on`; restoring the old helper copy also restores its old policy.

## Administrator certificates and trust

`RequiredRSASize` checks raw RSA keys and certificate **subjects**, not a certificate's
signing CA. `CASignatureAlgorithms` selects signature algorithms, not CA modulus sizes.
The general operator SSH configuration is retained by default and is not automatically
screened. For the supported strong configuration, use an explicit reviewed profile:

1. Keep strong existing private keys in their current file, agent or hardware provider.
   Inspect every selected public identity with `ssh-keygen -l -E sha256 -f identity.pub`.
   RSA must have at least 2048 actual bits; use Ed25519 or supported NIST curves for EC.
2. Inspect every selected user certificate with `ssh-keygen -L -E sha256 -f identity-cert.pub`.
   Match its Signing CA fingerprint to an independently obtained public CA file, and inspect
   **that file** with `ssh-keygen -l -E sha256 -f ca.pub` using the same floors. `-L` alone does
   not report CA size. Include automatically discovered `IdentityFile-cert.pub` candidates.
   An agent/provider may sign for a selected strong identity; review any certificate it can
   offer for that identity too. Remove weak or unreviewed candidates from this profile.
3. Build a dedicated `known_hosts` with only reviewed raw keys and/or reviewed
   `@cert-authority` public keys. Apply the same CA/endpoint floors, verify host/principal
   bindings and fingerprints out of band, and keep strict host checking. Retain strong
   certificates; there is no need to replace them with unrelated credentials.
4. Write a private SSH configuration using absolute paths, for example:

   ```sshconfig
   Include /home/operator/.ssh/kyquickstart-ai/config
   Host admin.example.net
     User owner-admin
     IdentityFile /home/operator/.ssh/admin-ed25519
     CertificateFile /home/operator/.ssh/admin-ed25519-cert.pub
     IdentitiesOnly yes
   Host *
     UserKnownHostsFile /home/operator/.ssh/kyqs-reviewed-known_hosts
     GlobalKnownHostsFile /dev/null
     KnownHostsCommand none
     VerifyHostKeyDNS no
     StrictHostKeyChecking yes
     HostbasedAuthentication no
     GSSAPIAuthentication no
   ```

   Retain necessary port, provider and identity-agent settings in this reviewed file.
   Omit `CertificateFile` for a raw identity. OpenSSH `-F` ignores normal user and system
   configurations: explicitly include the managed Ky file as shown, and do not include an
   unreviewed fallback. Its managed aliases retain their separately pinned Ed25519 host keys.
   Configure every admin destination used by `add-host` and `revoke`, including the actual
   address passed to those commands. A manual admin alias alone may not match that address.
5. Export the path for every launcher/helper invocation, including resume and handover:

   ```sh
   export KYQS_SSH_CONFIG=/home/operator/.ssh/kyqs-reviewed-config
   ./bin/ssh-policy -G admin.example.net
   ./kyqs-ai hosts
   ```

   Inspect the effective identities, certificate files and trust files before first use.
   The path must remain exported in later shells; the launcher does not store or audit the
   contents of this operator-owned file. A missing/unreadable selected file is refused.

ProxyJump/ProxyCommand can create additional transports. If needed, put their own SSH calls
through this policy and a separately reviewed profile; an independently spawned proxy does
not automatically inherit destination options. Test each hop before transmitting credentials.

## Scope and checks

The policy covers SSH invoked by the fixed launcher/helpers. The selected agent can still run
arbitrary direct commands under its existing permission model. Model-provider CLI TLS,
git/HTTPS updates, Kubernetes control-plane policy and KyQuickStart's own transports are
separate; this document does not attest whole-product OpenSSF compliance or a deployed server.

`test/unit.sh` checks the effective installed client policy, capability refusal and retention
of its maintained PQ defaults. `test/e2e.sh` exercises onboarding, pinning, secrets, copied
helpers and revoke. After it builds the disposable sshd image, `test/ssh-policy.sh` exercises
real weak/strong negotiations, certificate subjects, old-master bypass and isolated CA trust.

OpenSSH sources: [RequiredRSASize](https://man.openbsd.org/ssh_config#RequiredRSASize),
[`-F`](https://man.openbsd.org/ssh#F),
[certificate format](https://github.com/openssh/openssh-portable/blob/V_9_3_P2/PROTOCOL.certkeys),
[RSA size checker](https://github.com/openssh/openssh-portable/blob/V_9_3_P2/sshkey.c#L1323).
