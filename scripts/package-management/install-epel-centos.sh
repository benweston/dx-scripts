#!/usr/bin/env bash
# -------------------------------------------------------------------------
# Script Name: install-epel-centos.sh
# Description: Installs the Extra Packages for Enterprise Linux (EPEL)
#              repository on CentOS-based systems to enable access to
#              additional software packages.
#
# Version:     1.0
# Author:      Ben Weston
# Last Updated: 2025-12-05
#
# Supported OS:
#   - CentOS 7 / 8
#   - RHEL 7 / 8 (with appropriate subscription)
#   - AlmaLinux / Rocky Linux (via epel-release package)
#
# Usage:
#   sudo ./install-epel-centos.sh
#
# Notes:
#   - Requires internet access to download the EPEL release package.
#   - Always verify compatibility with your specific CentOS/RHEL version.
# -------------------------------------------------------------------------

set -euo pipefail

# 1. Enable CodeReady Linux Builder repository
sudo dnf config-manager --set-enabled crb

# 2. Install EPEL
sudo dnf install -y epel-release epel-next-release
