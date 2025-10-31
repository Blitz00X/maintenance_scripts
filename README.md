# Linux Maintenance Script (LMS)

The **Linux Maintenance Script (LMS)** is a modular Bash toolkit that scans a Debian/Ubuntu system for 100 of the most common operational issues, explains each finding, and auto-remediates safe fixes on demand. It produces colorised terminal output and persists every run to a timestamped report for auditing.

## Highlights

- ✅ **100 production-grade checks** across networking, storage, packages, performance, security, systemd, and log hygiene.
- 🛠️ **Optional auto-fix mode** (`--fix`) that safely executes curated remediation commands.
- 🧠 **Explain mode** (`--explain`) that expands each issue into a human-friendly paragraph.
- 📝 **Structured reports** saved under `lms/reports/report_<timestamp>.txt` for post-run review.
- 🎯 **VS Code F5 integration**—launch LMS straight from the debugger with or without flags.

## Repository Layout

```
lms/
├── lms.sh                # Main orchestrator
├── modules/              # Category-specific diagnostics (10–15 checks each)
│   ├── network.sh        # Connectivity, DNS, routing
│   ├── disk.sh           # Capacity, SMART, mounts
│   ├── package.sh        # APT, dpkg, snaps/flatpaks
│   ├── performance.sh    # Resources, thermal, process health
│   ├── security.sh       # SSH hardening, sysctl, updates
│   ├── system.sh         # Core services, timers, identity
│   └── log.sh            # Journald, rotation, auth anomalies
├── utils/                # Shared helpers
│   ├── colors.sh         # ANSI palettes
│   ├── helper.sh         # Printing + run helpers
│   └── logger.sh         # Issue tracking + reporting
├── reports/              # Generated audit logs
└── run.js                # VS Code debug entrypoint
```

## Prerequisites

- Bash 5+
- Core GNU utilities (`awk`, `sed`, `grep`, `find`, etc.)
- Systemd-based distribution (tested on Debian/Ubuntu)
- Optional tooling for richer checks: `smartctl` (SMART), `flatpak`, `snap`, `coredumpctl`, etc.—missing tools gracefully downgrade checks to warnings.
- Node.js ≥ 16 **only if** you plan to run via VS Code F5 (for the `run.js` launcher).

## Running LMS

### Direct from the terminal

```bash
# Standard read-only scan
bash lms/lms.sh

# Apply auto-remediations where safe
bash lms/lms.sh --fix

# Add verbose explanations with remediation advice
bash lms/lms.sh --fix --explain

# Customise report path
bash lms/lms.sh --report /tmp/lms_report.txt
```

Every invocation prints a colorised summary and writes a full audit trail to `lms/reports/` (or your chosen `--report` destination).

### From Visual Studio Code (F5)

The repo ships with a `.vscode/launch.json` profile bundle. Press **F5** (or open the Run & Debug panel) and select one of:

1. **Run LMS** – basic read-only scan.
2. **Run LMS (Fix)** – enables `--fix`.
3. **Run LMS (Explain)** – enables `--explain`.
4. **Run LMS (Fix + Explain)** – combines both flags.

The Node wrapper at `lms/run.js` simply spawns `bash lms/lms.sh …`, so results appear in the integrated terminal exactly as they would from a shell.

## Check Catalogue (Overview)

| Category      | Example Check Codes | Focus Areas |
| ------------- | ------------------- | ----------- |
| Network       | `NET001–NET015`     | Connectivity, DNS, latency, NTP, SSH exposure |
| Disk          | `DISK001–DISK015`   | Capacity, inodes, SMART, RAID, swap |
| Package       | `PKG001–PKG014`     | APT health, snaps/flatpaks, unattended updates |
| Performance   | `PERF001–PERF014`   | Load, RAM/swap, zombies, FD exhaustion |
| Security      | `SEC001–SEC014`     | SSH hardening, firewall, sysctl lockdown, updates |
| System        | `SYS001–SYS014`     | systemd health, timers, identity, symlink hygiene |
| Logs          | `LOG001–LOG014`     | Journal size/integrity, logrotate, auth anomalies |

> 📌 Each check publishes: `CODE`, `MESSAGE`, `REASON`, `FIX`, and a status (`ok`, `pending`, `fixed`, `failed`). Auto-fixes increment the report’s “Auto-fixed” counter, while pending items document the suggested follow-up.

## Customisation Tips

- Extend modules by adding new `check_*` functions following the existing pattern (`CODE`, `MESSAGE`, `REASON`, `FIX`, and a call to `log_issue`).
- To add new auto-remediations, wrap commands with `attempt_fix_cmd "Description" "sudo ..."` so they only execute when `--fix` is supplied.
- Colour palette tweaks live in `utils/colors.sh`; printing utilities are concentrated in `utils/helper.sh`.
- Reports default to `reports/report_<timestamp>.txt`. Update `prepare_environment` in `lms.sh` if you need alternate retention rules.

## FAQ

**Do I need to run LMS as root?**  
Read-only scans can run unprivileged. Auto-fixes (`--fix`) rely on `sudo` to elevate the curated remediation commands.

**What if a check relies on a missing tool (e.g., `smartctl`)?**  
The check logs a warning (`record_check_skip`) so you know which dependency to install, but keeps the run moving.

**Can I integrate this into CI/CD?**  
Yes—invoke `bash lms/lms.sh --report /path/to/artifact.txt` inside your pipeline. Exiting with a non-zero status indicates LMS encountered an error rather than a degraded system state (detected issues still return exit code 0 to allow automated triage).

---

Feel free to adapt the module catalogue to match your environment (e.g., RHEL-based using `dnf`, or servers without systemd). Contributions welcome!
