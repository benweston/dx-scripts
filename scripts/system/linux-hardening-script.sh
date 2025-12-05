#!/bin/bash
# Harden the kernel by disabling unused kernel modules on a Google Cloud VM

set -euo pipefail

# Define an array of kernel modules to disable
MODULES_TO_DISABLE=(
    floppy         # Legacy floppy disk support
    bluetooth      # Bluetooth support (not needed on VMs)
    firewire-core  # FireWire support (not needed on GCP)
    thunderbolt    # Thunderbolt support (not needed on GCP)
    usb-storage    # Prevents USB storage devices from being used
    cramfs         # Obsolete compressed filesystem
    freevxfs       # Obsolete SCO Unix filesystem
    jffs2          # Obsolete flash filesystem
    hfs            # Legacy Mac OS filesystem
    hfsplus        # Newer Mac OS filesystem (not needed)
    squashfs       # Read-only compressed filesystem (disable if not used)
    udf            # Optical disk filesystem (CD/DVD)
    dccp           # Rarely used transport protocol
    sctp           # Stream Control Transmission Protocol (not commonly needed)
    rds            # Reliable Datagram Sockets (not widely used)
    tipc           # Transparent Inter-Process Communication (rarely needed)
)

echo "Disabling unnecessary kernel modules..."

# Write to modprobe blacklist
BLACKLIST_CONF="/etc/modprobe.d/hardened-kernel.conf"
echo "# Hardened Kernel: Disable unused modules" | sudo tee "$BLACKLIST_CONF" > /dev/null

for module in "${MODULES_TO_DISABLE[@]}"; do
    echo "blacklist $module" | sudo tee -a "$BLACKLIST_CONF" > /dev/null
done

echo "Kernel modules blacklisted in $BLACKLIST_CONF."

# Ensure they cannot be loaded at runtime
for module in "${MODULES_TO_DISABLE[@]}"; do
    if lsmod | grep -q "$module"; then
        echo "Unloading module: $module"
        sudo rmmod "$module" || echo "Warning: Could not unload $module (might be built-in)."
    fi
done

echo "Applying changes..."
sudo update-initramfs -u || sudo dracut -f  # Works for Debian/Ubuntu and RHEL/CentOS

echo "Kernel hardening complete. Reboot is recommended."