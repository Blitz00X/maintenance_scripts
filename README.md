# Linux Maintenance Script (LMS)

The **Linux Maintenance Script (LMS)** is a modular Bash toolkit that scans a Debian/Ubuntu system for the most common operational issues across networking, storage, firmware, containers, and services, explains each finding, and auto-remediates safe fixes on demand. It produces colorised terminal output and persists every run to a timestamped report for auditing.

## Highlights

-  **189 production-grade checks** across networking, storage, packages, containers, performance, security, firmware, boot/UEFI, systemd, and log hygiene.
-  **Optional auto-fix mode** (`--fix`) that safely executes curated remediation commands.
-  **Explain mode** (`--explain`) that expands each issue into a human-friendly paragraph.
-  **Structured reports** (Text & JSON) saved under `lms/reports/` for post-run review.
-  **VS Code F5 integration**—launch LMS straight from the debugger with or without flags.

## Repository Layout

```
lms.sh                    # Top-level wrapper (./lms.sh)
verify_checks.sh          # Lists and counts check_* functions in lms/modules
lms/
├── lms.sh                # Main orchestrator
├── config.example.sh     # Copy to config.sh for custom settings
├── modules/              # Category-specific diagnostics
│   ├── network.sh        # Connectivity, DNS, routing
│   ├── disk.sh           # Capacity, SMART, mounts
│   ├── package.sh        # APT, dpkg, snaps/flatpaks, needrestart, livepatch
│   ├── container.sh      # Docker, Podman, containerd
│   ├── performance.sh    # Resources, thermal, PSI, systemd-oomd
│   ├── security.sh       # SSH hardening, firewall, sysctl, auditd, SELinux
│   ├── system.sh         # Core services, timers, identity
│   ├── firmware.sh       # fwupd, microcode packages, LVFS metadata
│   ├── boot.sh           # systemd-boot (bootctl), Secure Boot, ESP mount
│   └── log.sh            # Journald, rotation, auth anomalies
├── utils/                # Shared helpers
│   ├── colors.sh         # ANSI palettes
│   ├── helper.sh         # Printing + dependency helpers
│   └── logger.sh         # Issue tracking + Text/JSON reporting
├── reports/              # Generated audit logs
└── run.js                # VS Code debug entrypoint
```

## Prerequisites

- Bash 5+
- Core GNU utilities (`awk`, `sed`, `grep`, `find`, etc.)
- Systemd-based distribution (tested on Debian/Ubuntu)
- Optional tooling for richer checks: `smartctl` (SMART), `flatpak`, `snap`, `coredumpctl`, `fwupdmgr`, `needrestart`, `docker`/`podman`, `bootctl`, `mokutil`, etc.—missing tools gracefully downgrade checks to warnings (`record_check_skip`).
- Node.js ≥ 16 **only if** you plan to run via VS Code F5 (for the `run.js` launcher).

## Quick Start

```bash
git clone https://github.com/<your-org>/maintenance_scripts.git
cd maintenance_scripts
./lms.sh
```

The wrapper ensures the core script runs with the right paths—no extra setup required.

## Running LMS

### Direct from the terminal

```bash
# Standard read-only scan
./lms.sh

# Apply auto-remediations where safe
./lms.sh --fix

# Add verbose explanations with remediation advice
./lms.sh --fix --explain

# Generate a machine-readable JSON report
./lms.sh --json

# Customise report path
./lms.sh --report /tmp/lms_report.txt
```

Every invocation prints a colorised summary and writes a full audit trail to `lms/reports/` (or your chosen `--report` destination).

## Configuration

- Copy the sample config: `cp lms/config.example.sh lms/config.sh`.
- Edit `lms/config.sh` to:
  - toggle modules via `LMS_ENABLED_MODULES=(network disk package container …)`,
  - set default behaviour (`LMS_DEFAULT_AUTO_FIX`, `LMS_DEFAULT_EXPLAIN`),
  - point reports to another directory, or
  - bake in default arguments (`LMS_DEFAULT_ARGS`).

The config is optional—if it’s absent, LMS falls back to the bundled defaults.

### From Visual Studio Code (F5)

The repo ships with a `.vscode/launch.json` profile bundle. Press **F5** (or open the Run & Debug panel) and select one of:

1. **Run LMS** – basic read-only scan.
2. **Run LMS (Fix)** – enables `--fix`.
3. **Run LMS (Explain)** – enables `--explain`.
4. **Run LMS (Fix + Explain)** – combines both flags.

The Node wrapper at `lms/run.js` simply spawns `./lms.sh …`, so results appear in the integrated terminal exactly as they would from a shell.

## Check Catalogue (Overview)

| Category      | Example Check Codes | Focus Areas |
| ------------- | ------------------- | ----------- |
| Network       | `NET001–NET050`     | Connectivity, DNS, latency, NTP, SSH exposure |
| Disk          | `DISK001–DISK050`   | Capacity, inodes, SMART, RAID, swap |
| Package       | `PKG001–PKG016`     | APT health, snaps/flatpaks, unattended updates, needrestart, Livepatch |
| Container     | `CTR001–CTR005`     | Docker daemon, disk, Podman, containerd, rootless |
| Performance   | `PERF001–PERF016`   | Load, RAM/swap, zombies, FD exhaustion, PSI, systemd-oomd |
| Security      | `SEC001–SEC016`     | SSH hardening, firewall, sysctl, auditd, SELinux, updates |
| System        | `SYS001–SYS014`     | systemd health, timers, identity, symlink hygiene |
| Firmware      | `FWU001–FWU005`     | fwupd service, upgrades, metadata cache, CPU microcode |
| Boot          | `BOOT001–BOOT003`   | systemd-boot status, Secure Boot, EFI mount |
| Logs          | `LOG001–LOG014`     | Journal size/integrity, logrotate, auth anomalies |

>  Each check publishes: `CODE`, `MESSAGE`, `REASON`, `FIX`, and a status (`ok`, `pending`, `fixed`, `failed`). Auto-fixes increment the report’s “Auto-fixed” counter, while pending items document the suggested follow-up.

## Customisation Tips

- Extend modules by adding new `check_*` functions following the existing pattern (`CODE`, `MESSAGE`, `REASON`, `FIX`, and a call to `log_issue`).
- To add new auto-remediations, wrap commands with `attempt_fix_cmd "Description" "sudo ..."` so they only execute when `--fix` is supplied.
- Colour palette tweaks live in `utils/colors.sh`; printing utilities are concentrated in `utils/helper.sh`.
- Optional tuning: `LMS_FWU_METADATA_STALE_DAYS` (firmware metadata freshness), `LMS_DOCKER_ROOT_PCT_WARN` (Docker root filesystem usage), `LMS_PSI_MEM_AVG10_WARN` (memory PSI threshold)—export before running or set in `config.sh`.
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

## License

This project is released under the [GNU General Public License v3.0](./LICENSE). By using or distributing LMS you agree to the terms of the GPLv3, including the requirement to share source modifications under the same license.
