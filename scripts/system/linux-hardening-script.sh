#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Script Name:      linux-hardening-script.sh
# Description:      Harden the kernel by disabling unused kernel modules
#
# Version:          1.1
# Author:           Ben Weston
# Last Updated:     2025-12-05
#
# Supported OS:
#   -   CentOS / RHEL-based distributions
#   -   Ubuntu / Debian-based distributions
#
# Usage:
#   # dry-run (no changes)
#   ./linux-hardening-script.sh --dry-run
#
#   # perform changes
#   sudo ./linux-hardening-script.sh
#
#   # revert to most recent backup
#   sudo ./linux-hardening-script.sh --revert
#
# Notes:
#   - Review all actions before running on production systems.
#   - Running without sudo will still attempt to call sudo for privileged ops.
#   - Revert restores the latest backup of /etc/modprobe.d/hardened-kernel.conf
# ------------------------------------------------------------------------------

set -euo pipefail

# ----------------------------
# Configuration
# ----------------------------
BLACKLIST_CONF="/etc/modprobe.d/hardened-kernel.conf"
BACKUP_PREFIX="${BLACKLIST_CONF}.bak"
KERNEL_DIR="/lib/modules/$(uname -r)"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"

MODULES_TO_DISABLE=(
    floppy
    bluetooth
    firewire-core
    thunderbolt
    usb-storage
    cramfs
    freevxfs
    jffs2
    hfs
    hfsplus
    squashfs
    udf
    dccp
    sctp
    rds
    tipc
)

# ----------------------------
# CLI flags
# ----------------------------
DRY_RUN=false
REVERT=false

while [[ "${#}" -gt 0 ]]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=true; shift ;;
        -r|--revert)  REVERT=true; shift ;;
        -h|--help)
            cat <<EOF
Usage:
  ${0} [--dry-run]         Show actions without making changes.
  ${0}                     Perform hardening (requires sudo for actions).
  sudo ${0} --revert       Restore the most recent backup of the blacklist.
Options:
  -n, --dry-run    Do not modify files or unload modules; print actions only.
  -r, --revert     Restore latest backup of ${BLACKLIST_CONF}.
  -h, --help       Show this help.
EOF
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            exit 2
            ;;
    esac
done

# ----------------------------
# Colours / logging helpers
# ----------------------------
# Use colours only if stdout is a terminal
if [[ -t 1 ]]; then
    RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BLUE=$'\e[34m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; RESET=''
fi

info()    { echo -e "${BLUE}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[OK]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
err()     { echo -e "${RED}[ERROR]${RESET} $*"; }

# ----------------------------
# Utility functions
# ----------------------------
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

module_exists_on_disk() {
    local mod="$1"
    # Prefer modinfo if available
    if command_exists modinfo; then
        if modinfo "$mod" >/dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    fi

    # Fallback: look for module .ko in modules.dep
    if [[ -f "${KERNEL_DIR}/modules.dep" ]]; then
        if grep -qE "/${mod}(\.ko)?\b" "${KERNEL_DIR}/modules.dep"; then
            return 0
        fi
    fi

    return 1
}

blacklist_contains() {
    local mod="$1"
    if [[ -f "$BLACKLIST_CONF" ]]; then
        if grep -Fxq "blacklist $mod" "$BLACKLIST_CONF"; then
            return 0
        fi
    fi
    return 1
}

backup_blacklist() {
    if [[ -f "$BLACKLIST_CONF" ]]; then
        local bak="${BACKUP_PREFIX}.${TIMESTAMP}"
        if $DRY_RUN; then
            info "Would create backup: ${bak}"
        else
            sudo cp -p "$BLACKLIST_CONF" "${bak}"
            success "Backup created: ${bak}"
        fi
    else
        info "No existing ${BLACKLIST_CONF} to backup."
    fi
}

restore_latest_backup() {
    local latest
    latest=$(ls -1 "${BACKUP_PREFIX}."* 2>/dev/null | sort -r | head -n1 || true)
    if [[ -z "$latest" ]]; then
        err "No backups found to restore (looked for ${BACKUP_PREFIX}.*)."
        exit 1
    fi

    if $DRY_RUN; then
        info "Would restore backup: ${latest} -> ${BLACKLIST_CONF}"
    else
        sudo cp -p "$latest" "$BLACKLIST_CONF"
        success "Restored ${latest} -> ${BLACKLIST_CONF}"
    fi

    # Rebuild initramfs after restore
    if $DRY_RUN; then
        info "Would rebuild initramfs (dry-run)."
    else
        rebuild_initramfs
    fi

    info "Revert complete. Consider rebooting if necessary."
}

rebuild_initramfs() {
    if command_exists update-initramfs; then
        info "Running update-initramfs -u ..."
        sudo update-initramfs -u
        success "update-initramfs completed."
    elif command_exists dracut; then
        info "Running dracut -f ..."
        sudo dracut -f
        success "dracut completed."
    else
        err "Neither update-initramfs nor dracut found; cannot rebuild initramfs."
        return 1
    fi
}

unload_module_runtime() {
    local mod="$1"
    if ! command_exists rmmod; then
        warn "rmmod not found; skipping runtime unload for ${mod}."
        return 0
    fi

    if lsmod | awk '{print $1}' | grep -xq "${mod}"; then
        if $DRY_RUN; then
            info "Would attempt to unload module: ${mod}"
        else
            info "Attempting to unload module: ${mod}"
            if sudo rmmod "${mod}"; then
                success "Unloaded ${mod}"
            else
                warn "Could not unload ${mod} (might be built-in or in-use)."
            fi
        fi
    else
        info "Module ${mod} not loaded at runtime."
    fi
}

# ----------------------------
# Main
# ----------------------------
if $REVERT; then
    info "Running in revert mode: restoring latest backup of ${BLACKLIST_CONF}."
    restore_latest_backup
    exit 0
fi

info "Starting kernel hardening script"
if $DRY_RUN; then
    info "Dry-run enabled: no changes will be made."
fi

# Ensure we are on Linux
if [[ "$(uname -s)" != "Linux" ]]; then
    err "This script is intended to run on Linux only."
    exit 1
fi

# Backup existing blacklist (if any)
backup_blacklist

# If not dry-run, create/overwrite header in blacklist file
if $DRY_RUN; then
    info "Would create/overwrite ${BLACKLIST_CONF} with header."
else
    echo "# Hardened Kernel: Disable unused modules (created ${TIMESTAMP})" | sudo tee "$BLACKLIST_CONF" > /dev/null
fi

# Process modules
for mod in "${MODULES_TO_DISABLE[@]}"; do
    if module_exists_on_disk "$mod"; then
        if blacklist_contains "$mod"; then
            info "Already blacklisted: ${mod} (skipping)"
        else
            if $DRY_RUN; then
                info "Would add to blacklist: ${mod}"
            else
                info "Blacklisting kernel module: ${mod}"
                echo "blacklist ${mod}" | sudo tee -a "$BLACKLIST_CONF" > /dev/null
            fi
            # Attempt to unload at runtime (subject to dry-run)
            unload_module_runtime "$mod"
        fi
    else
        info "Skipping: module '${mod}' not present in this kernel."
    fi
done

info "Kernel modules processing complete."

# Rebuild initramfs to persist changes
if $DRY_RUN; then
    info "Would rebuild initramfs now (dry-run)."
else
    info "Rebuilding initramfs to persist blacklists..."
    rebuild_initramfs
fi

success "Kernel hardening complete. Reboot is recommended."

exit 0
