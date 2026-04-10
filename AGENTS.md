# AGENTS.md

## Cursor Cloud specific instructions

### Project overview

This repository contains a single Bash script (`agent.sh`) — the **Purple Team Agent v3.0**, a red team simulation framework for authorized purple team security exercises. It runs from WSL (Windows Subsystem for Linux) and executes PowerShell commands against a Windows host.

### Development tools

- **Linting**: `shellcheck agent.sh` — the only dev dependency. Install with `sudo apt-get install -y shellcheck` if missing.
- **Running**: `bash agent.sh [OPTIONS]` — see `--help` and `--list` for usage.
- **No build step**: The script is self-contained with no package manager, no build system, and no external dependencies beyond standard Unix utilities and bash.

### Important caveats

- **WSL requirement**: The script's `detect_environment()` function checks `/proc/version` for "microsoft" and exits immediately if not running in WSL. On a standard Linux VM (including Cursor Cloud), `bash agent.sh --phase 1` (or any phase) will exit with `"Not running in WSL environment"`. This is expected and correct behavior.
- **Safe operations**: `--help` and `--list` do not require WSL and work on any Linux system. These are the primary commands available for testing in non-WSL environments.
- **No tests directory**: There is no automated test suite. Validation is done via `shellcheck` for static analysis and manual execution on a WSL+Windows system for functional testing.
