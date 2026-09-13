#!/usr/bin/env bash
set -Eeuo pipefail
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export LINT_TOP="${LINT_TOP:-line_ping_pong_capture}"
export LINT_ENTRY="${LINT_ENTRY:-rtl/line_ping_pong_capture.sv}"

backend="${BACKEND:-custom}"
case "$backend" in
	custom)
		macro=""
		;;
	agg23-word)
		macro="SDRAM_BACKEND_AGG23_WORD=1"
		export LINT_FLAGS="${LINT_FLAGS:-} -DSDRAM_BACKEND_AGG23_WORD"
		;;
	agg23-burst)
		macro="SDRAM_BACKEND_AGG23_BURST=1"
		export LINT_FLAGS="${LINT_FLAGS:-} -DSDRAM_BACKEND_AGG23_BURST"
		;;
	agg23-bl8-write)
		macro="SDRAM_BACKEND_AGG23_BL8_WRITE=1"
		export LINT_FLAGS="${LINT_FLAGS:-} -DSDRAM_BACKEND_AGG23_BL8_WRITE"
		;;
	007-bl8-hwtest)
		macro="SDRAM_BACKEND_AGG23_BL8_WRITE=1"
		export LINT_FLAGS="${LINT_FLAGS:-} -DSDRAM_BACKEND_AGG23_BL8_WRITE"
		;;
	all)
		for b in custom agg23-word agg23-burst agg23-bl8-write; do
			printf '\n=== Building BACKEND=%s ===\n' "$b"
			BACKEND="$b" "$0" "$@"
		done
		exit 0
		;;
	*)
		printf 'Unknown BACKEND=%s (expected custom, agg23-word, agg23-burst, agg23-bl8-write, 007-bl8-hwtest, or all)\n' "$backend" >&2
		exit 1
		;;
esac

qsf="${SCRIPT_DIR}/Template.qsf"
backup="${SCRIPT_DIR}/build/Template.qsf.pre-backend"
mkdir -p "${SCRIPT_DIR}/build"
cp "$qsf" "$backup"
restore_qsf() {
	cp "$backup" "$qsf"
}
trap restore_qsf EXIT

if [[ -n "$macro" ]]; then
	printf '\n# Temporary backend selection from build.sh\nset_global_assignment -name VERILOG_MACRO "%s"\n' "$macro" >>"$qsf"
fi

EXPERIMENT_DIR="$SCRIPT_DIR" "${SCRIPT_DIR}/../harness/build-quartus-experiment" "$@"
cp "${SCRIPT_DIR}/output_files/Template.rbf" "${SCRIPT_DIR}/output_files/Template-${backend}.rbf"
for suffix in asm.rpt fit.rpt fit.summary flow.rpt map.rpt map.summary sta.rpt sta.summary; do
	if [[ -f "${SCRIPT_DIR}/output_files/Template.${suffix}" ]]; then
		cp "${SCRIPT_DIR}/output_files/Template.${suffix}" "${SCRIPT_DIR}/output_files/Template-${backend}.${suffix}"
	fi
done
printf 'Backend RBF: %s\n' "${SCRIPT_DIR}/output_files/Template-${backend}.rbf"
