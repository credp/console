#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_FILE="${PROJECT_FILE:-Template.qpf}"
readonly PROJECT_REVISION="${PROJECT_FILE%.qpf}"
readonly QUARTUS_ROOTDIR="${QUARTUS_ROOTDIR:-/home/chris/intelFPGA_lite/17.0/quartus}"
readonly QUARTUS_SH="${QUARTUS_SH:-${QUARTUS_ROOTDIR}/bin/quartus_sh}"
readonly VERILATOR="${VERILATOR:-/usr/bin/verilator}"
readonly LINT_TOP="${LINT_TOP:-emu}"
readonly LINT_ENTRY="${LINT_ENTRY:-Template.sv}"
readonly BUILD_DIR="${BUILD_DIR:-${SCRIPT_DIR}/build}"
readonly QUARTUS_LOG="${BUILD_DIR}/quartus.log"
readonly EXPECTED_RBF="${SCRIPT_DIR}/output_files/${PROJECT_REVISION}.rbf"

export QUARTUS_ROOTDIR
export LM_LICENSE_FILE="${LM_LICENSE_FILE:-/home/chris/intelFPGA_lite/17.0/LR-186265_License.dat}"
export PATH="${QUARTUS_ROOTDIR}/bin:/usr/local/bin:/usr/bin:/bin"

die() {
    printf 'build: %s\n' "$*" >&2
    exit 1
}

[[ -f "${SCRIPT_DIR}/${PROJECT_FILE}" ]] ||
    die "project file not found: ${SCRIPT_DIR}/${PROJECT_FILE}"
[[ -x "$QUARTUS_SH" ]] ||
    die "Quartus Shell not found or not executable: $QUARTUS_SH"
[[ -x "$VERILATOR" ]] ||
    die "Verilator not found or not executable: $VERILATOR"
[[ -f "${SCRIPT_DIR}/${LINT_ENTRY}" ]] ||
    die "Verilator lint entry file not found: ${SCRIPT_DIR}/${LINT_ENTRY}"
[[ -r "$LM_LICENSE_FILE" ]] ||
    die "Quartus licence file not readable: $LM_LICENSE_FILE"

quartus_version="$("$QUARTUS_SH" --version 2>&1)" ||
    die "unable to run Quartus Shell: $QUARTUS_SH"
printf '%s\n' "$quartus_version"
grep -q 'Version 17\.0' <<<"$quartus_version" ||
    die "Quartus 17.0 is required"
printf '%s\n' "$("$VERILATOR" --version)"

cd "$SCRIPT_DIR"
mkdir -p "$BUILD_DIR"

lint_include_dir="$(mktemp -d "${TMPDIR:-/tmp}/mister-lint.XXXXXX")"
trap 'rm -rf -- "$lint_include_dir"' EXIT
cat >"${lint_include_dir}/quartus_stubs.sv" <<'EOF'
module lcell(input wire in, output wire out);
    assign out = in;
endmodule

module pll (
    input  wire refclk,
    input  wire rst,
    output wire outclk_0,
    output wire locked
);
    assign outclk_0 = refclk;
    assign locked   = ~rst;
endmodule

module hps_io #(
    parameter CONF_STR = ""
) (
    input  wire         clk_sys,
    inout  wire [45:0]  HPS_BUS,

    output wire         EXT_BUS,
    output wire         gamma_bus,

    output wire         forced_scandoubler,
    output wire [1:0]   buttons,
    output wire [127:0] status,
    input  wire         status_menumask,
    output wire [10:0]  ps2_key
);

    assign forced_scandoubler = 1'b0;
    assign buttons            = 2'b00;
    assign status             = 128'b0;
    assign ps2_key            = 11'b0;
    assign EXT_BUS   = 1'b0;
    assign gamma_bus = 1'b0;

endmodule
EOF

printf 'Generating build ID...\n'
"$QUARTUS_SH" -t sys/build_id.tcl dummy "$PROJECT_REVISION" "$PROJECT_REVISION"

printf 'Linting with Verilator...\n'
"$VERILATOR" \
    --lint-only \
    --language 1800-2017 \
    --top-module "$LINT_TOP" \
    --error-limit 0 \
    -I. \
    -y rtl \
    +libext+.v+.sv \
    -Wall \
    -Wno-fatal \
    -Wwarn-PINMISSING \
    -Wwarn-PINCONNECTEMPTY \
    -Wwarn-WIDTH \
    -Werror-LATCH \
    -Werror-MULTIDRIVEN \
    -Werror-UNDRIVEN \
    "${lint_include_dir}/quartus_stubs.sv" \
    "$LINT_ENTRY"

rm -rf -- "$lint_include_dir"
trap - EXIT

printf 'Compiling %s with Quartus (full log: %s)...\n' "$PROJECT_FILE" "$QUARTUS_LOG"
if ! "$QUARTUS_SH" --flow compile "$PROJECT_FILE" >"$QUARTUS_LOG" 2>&1; then
    tail -n 40 "$QUARTUS_LOG" >&2
    die "Quartus compilation failed; see $QUARTUS_LOG"
fi

[[ -f "$EXPECTED_RBF" ]] ||
    die "Quartus completed but expected output was not produced: $EXPECTED_RBF"

printf 'Build succeeded: %s\n' "$EXPECTED_RBF"
