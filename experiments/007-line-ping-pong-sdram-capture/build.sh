#!/usr/bin/env bash
set -Eeuo pipefail
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export LINT_TOP="${LINT_TOP:-line_ping_pong_capture}"
export LINT_ENTRY="${LINT_ENTRY:-rtl/line_ping_pong_capture.sv}"
EXPERIMENT_DIR="$SCRIPT_DIR" exec "${SCRIPT_DIR}/../harness/build-quartus-experiment" "$@"
