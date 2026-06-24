# TODO

Tracked work items for Migratron. Items are moved from here to `CHANGELOG.md` when completed.

---

## Completed in MVP

- [x] **USMT System Auditor (`scripts/scan-system.ps1`)** — Audits the host computer for USMT binaries, rule XMLs, active OneDrive folders, and previous ZIP archives.
- [x] **USMT Snapshot Backup Script (`scripts/backup-profile.ps1`)** — Invokes `scanstate.exe` elevated, stages `USMT.MIG` stores, compresses them to OneDrive output folders, and handles retention count cleanups.
- [x] **USMT Snapshot Restorer (`scripts/restore-profile.ps1`)** — Safely unpacks backup ZIP files and calls `loadstate.exe` to import settings, files, and registry states.
- [x] **Scheduled Task Manager (`scripts/schedule-task.ps1`)** — Supports registering and unregistering Windows Scheduled Tasks running elevated under current user security credentials (Daily, logon, or idle).
- [x] **Interactive CLI Menu (`migratron.ps1`)** — Central driver featuring command parameter routing and a console dashboard.
- [x] **Declarative Schema Configuration (`scripts/usmt-config.json`)** — Houses execution preferences (directories, custom XML rules, retention thresholds, triggers).

---

## Completed in v1.1.0 (Upcoming)

- [x] **Secure Archive Encryption** — Fully implement the `encrypt: true` config placeholder. Add password protection to safeguard credentials and private keys, either by wrapping the final ZIP archive with AES encryption or by piping a password into USMT's native `/encrypt` flag during the `scanstate` pass.
- [x] **Include Paths Mode (`backup.includePaths`)** — Allow users to specify an explicit list of paths to capture instead of relying on MigApp.xml/MigUser.xml defaults. Generates `IncludeCustom.xml` using USMT `<unconditionalInclude>` rules. Pairs naturally with the existing `excludePaths` mechanism.
- [x] **Advanced GFS Retention Policy** — Implement a Grandfather-Father-Son (GFS) backup rotation scheme (e.g., keep last 7 daily, 4 weekly, and 3 monthly backups). This would replace the flat `retentionCount` integer with a structured JSON object allowing users to keep historical known-good states over longer periods for disaster recovery, rather than strictly keeping the last $N$ chronological snapshots.
- [x] **Archive Contents Viewer** — Explore using `usmtutils.exe` (potentially `usmtutils /verify` or another extraction/parsing method) to generate a readable manifest/HTML/text view of exactly what was captured inside the `.MIG` file.
- [x] **Interactive CLI Enhancements** — Add more configuration options to the interactive CLI menu (`migratron.ps1`). Allow users to actively toggle backup retention types (Simple vs GFS), toggle encryption on/off, and manually type in the encryption key directly from the dashboard. Added a global `[Q] Quit` hotkey.
- [x] **Encoded Encryption Keys** — Support encoding the `encryptionKey` in `usmt-config.local.json` (e.g. using Base64 or DPAPI) so the password is not stored in plaintext on disk. Implement an `encryptionKeyEncoded: true/false` parameter to allow users to specify the format.

---

## Future Roadmap

- [ ] **OneDrive Sync Verification** — Check the local OneDrive sync status (using status attributes or querying client state) before completing the backup operation, ensuring the upload is in progress or completed.
- [ ] **Smart Service Layer (Windows Service)** — Create a lightweight background service wrapping the toolkit to monitor idle times, shutdown/logoff hooks, and orchestrate point-in-time snapshots intelligently.
- [ ] **USMT Custom XML Generator** — Create a utility to customise the rules inside the USMT XML files (excluding/including specific files, directories, or registry subkeys easily).
- [ ] **GitHub Actions Release Workflow** — Automates building the toolkit, creating a ZIP release archive, and attaching it to a new GitHub release with release notes.
- [ ] **Automatic Version Bump** — Script `update-version.ps1` updates `migratron.ps1` and `CHANGELOG.md` with the next semantic version before publishing. Bump script must be updated manually to update the next version number (but can be used to update existing release tags).
