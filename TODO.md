# TODO

Tracked work items for Migratron. Items are moved from here to `CHANGELOG.md` when completed.

---

## Future Roadmap

- [ ] **OneDrive Sync Verification** — Check the local OneDrive sync status (using status attributes or querying client state) before completing the backup operation, ensuring the upload is in progress or completed.
- [ ] **Smart Service Layer (Windows Service)** — Create a lightweight background service wrapping the toolkit to monitor idle times, shutdown/logoff hooks, and orchestrate point-in-time snapshots intelligently.
- [ ] **GitHub Actions Release Workflow** — Automates building the toolkit, creating a ZIP release archive, and attaching it to a new GitHub release with release notes.
- [ ] **Full-Archive Encryption** — Explore using `7-Zip` (`7z.exe`) or native methods to password-protect the entire output `.zip` wrapper (including manifests, configs, and logs) to prevent metadata leakage. Option should be in addition to the existing encryption configuration.
