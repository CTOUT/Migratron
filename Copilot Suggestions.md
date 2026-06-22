Use as suggestions only - use own judgement and research as needed.

---

# **Summary for AntiGravity: USMT‑Based User State Snapshot System (MVP Architecture)**

## **Objective**

Create a lightweight, reliable system that preserves _non‑synced user state_ (primarily AppData and application‑specific settings) across Windows reinstalls.  
This complements OneDrive/Microsoft Account sync by capturing the “miscellaneous” configuration data that Windows does not sync.

The system must support:

- Pre‑install capture
- Post‑install restore
- Storage via OneDrive
- Repeatable, low‑friction operation
- Future expansion into a smart background service

---

# **Core Technical Approach**

## **1. Use USMT as a Snapshot Engine**

USMT is used **not** as a continuous sync tool, but as a **point‑in‑time snapshot tool**.

It captures:

- AppData (Roaming + portable Local content)
- Application settings
- Registry‑linked user settings
- Miscellaneous profile data not synced by OneDrive

It does **not** capture:

- Installed applications
- System hives
- Start menu layouts
- Machine‑specific data

This aligns with the intended use case.

---

# **2. MVP = Scheduled Task + PowerShell Wrapper**

USMT is not suitable for continuous syncing, so the MVP uses:

### **A. PowerShell wrapper script**

Responsible for:

- Running `ScanState`
- Writing migration store to a OneDrive‑synced folder
- Logging
- Optional compression/encryption
- Optional OneDrive sync‑completion check

This script is the **core engine**.

### **B. Windows Scheduled Task**

Triggers the snapshot at predictable times:

- Daily
- On logoff
- On idle
- Or manually via automation

This avoids resource waste and aligns with USMT’s batch‑execution design.

---

# **3. OneDrive as the Transport Layer**

No custom sync engine is required.

OneDrive handles:

- Delta sync
- Conflict resolution
- Cloud storage
- Availability after reinstall

The system simply drops the migration store into a OneDrive folder.

---

# **4. Post‑Install Restore**

A second PowerShell script runs `LoadState` to restore the captured AppData and settings after Windows is reinstalled and OneDrive has synced the migration store back down.

Applications are reinstalled manually.

---

# **5. Future Expansion: Smart Service Layer (Optional)**

Once the MVP is stable, a lightweight Windows service can be added to provide:

- Idle detection
- Logoff/shutdown triggers
- OneDrive sync monitoring
- Snapshot freshness checks
- Local API for UI or automation
- Integration with Gemini/AntiGravity orchestration

The service **does not** run USMT continuously — it only orchestrates when snapshots occur.

This service will wrap the existing scripts rather than replace them.

---

# **6. Why This Architecture**

- USMT is a snapshot tool, not a sync engine
- Scheduled tasks provide predictable, low‑overhead execution
- Scripts keep logic simple and maintainable
- OneDrive handles transport and cloud storage
- Service layer can be added later without redesign
- Clean separation of concerns:
  - **Script = logic**
  - **Task = scheduling**
  - **Service = intelligence**
  - **OneDrive = transport**

---

# **Deliverables for MVP**

AntiGravity should design and implement:

### **1. PowerShell Snapshot Script**

- Runs USMT ScanState
- Outputs to OneDrive folder
- Logs success/failure
- Optional compression/encryption
- Optional sync‑completion check

### **2. Scheduled Task Definition**

- Runs elevated
- Configurable triggers
- Logs to Event Viewer

### **3. Post‑Install Restore Script**

- Runs LoadState
- Validates migration store
- Logs results

### **4. Folder Structure**

- OneDrive path for migration stores
- Versioning (timestamped snapshots)
- Cleanup policy

### **5. Roadmap for Smart Service**

- Idle/logoff detection
- Snapshot freshness logic
- OneDrive sync monitoring
- Optional UI/API integration

---

# **One‑Sentence Summary**

We’re building a **USMT‑powered snapshot system** that uses **scheduled tasks + PowerShell** for the MVP, with a future‑ready path to a **smart background service** that orchestrates snapshots intelligently without turning USMT into a continuous sync engine.
