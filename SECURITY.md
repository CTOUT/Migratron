# Security Policy

## Supported Versions

Migratron follows [Semantic Versioning](https://semver.org/). Security fixes are applied to the `main` branch and released as new versions.

| Version         | Supported |
| --------------- | --------- |
| `main` (latest) | Yes       |
| Older releases  | No        |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Open a [GitHub Security Advisory](https://github.com/CTOUT/Migratron/security/advisories/new) to report a vulnerability privately.


Include:

- A description of the vulnerability and its potential impact
- Steps to reproduce or a proof-of-concept
- Any suggested mitigations

You can expect:

- Acknowledgement within **48 hours**
- A status update within **7 days**
- Credit in the release notes if you would like it

## Scope

This repository contains:

- A PowerShell toolkit (`migratron.ps1`, `scripts/`)
- Declarative configuration (`scripts/usmt-config.json`, `scripts/usmt-config.local.json`)
- GitHub Actions release workflows
- Documentation

Vulnerabilities in any of these are in scope. Areas of particular interest:

- The backup script execution logic (parsing manifest files safely)
- PowerShell code injection when running custom commands defined in the manifest
- Directory traversal attacks when extracting or restoring files from backup archives
- Unintentional exposure of sensitive keys (SSH/GPG) or credentials (env vars, AWS configs)

## Key Security Practices for Users

### Backup Archive Security

Migratron backups contain highly sensitive data, including Git credentials, SSH configuration, shell profiles, and environment variables.

- **Never** upload Migratron backup ZIP archives to public repositories or shared cloud storage without password protection or encryption.
- Store backups in secure, encrypted storage (e.g., BitLocker-encrypted drives or secure personal cloud vaults).

### Sensitive Keys Warn-and-Skip

By default, Migratron scans for private SSH and GPG keys and alerts you if they are present. You can choose to exclude them or back them up only after acknowledging the warning.

## GitHub Actions

The release workflow (`release.yml`) pins all actions to full commit SHAs to prevent supply-chain compromise via mutable tags.
When updating actions, replace the SHA with the new release's commit SHA — do not revert to a mutable tag reference.
