# Getting started

## Requirements

Use Linux or macOS with Bash, OpenSSH 9.1 or later, Git, an SSH agent, a supported AI agent CLI and the `kyquickstart` binary on PATH. KyYard installation requires a KyQuickStart release binary. Docker targets need Docker Engine and the Compose plugin already installed; Podman is not supported. Kubernetes targets need an administrator kubeconfig, local `kubectl` and a persistent StorageClass. Prepare the domain and HTTPS hostnames. The installer does not install Docker or Kubernetes.

## Start the launcher

From the checkout, run `./kyqs-ai`. Choose this computer, remote servers, Kubernetes clusters or a mix, and choose an installed agent. The setup form records domain, apps, access, proxy/certificates, placement, identities, recovery and mail choices. Review its answers before the agent starts. For SSH targets, follow host preparation using your own administrator login and compare the host fingerprint.

Review the requested applications, separate administrator/everyday names and deployment plan before saying go. Docker-group access is root-equivalent even when the agent login has no sudo rights. Respect product placement: KyDrive, KyPost, KyDNS and KyMessages run on Docker; Euro-Office runs on Kubernetes. Consult the current KyQuickStart placement guide for the full matrix.
