#!/usr/bin/env sh
# SPDX-License-Identifier: Apache-2.0
# Start the deterministic Spike 002 sidecar on Linux/macOS.
# Managed hosts should set PZ_USER_DIR explicitly to their PZ user-data root.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PZ_USER_DIR=${PZ_USER_DIR:-"$HOME/Zomboid"}

exec python3 "$SCRIPT_DIR/whg_companion_sidecar.py" --pz-user-dir "$PZ_USER_DIR" "$@"
