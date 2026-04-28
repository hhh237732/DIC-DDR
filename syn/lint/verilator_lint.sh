#!/usr/bin/env bash
# ============================================================
# Verilator Lint Script for DDR3 Controller RTL
# Usage: bash syn/lint/verilator_lint.sh [--quiet]
# ============================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RTL_ROOT="${REPO_ROOT}/rtl"
QUIET="${1:-}"

RTL_FILES=(
    "${RTL_ROOT}/axi/sync_fifo.v"
    "${RTL_ROOT}/axi/axi_slave_if.v"
    "${RTL_ROOT}/cmd/addr_map.v"
    "${RTL_ROOT}/cmd/cmd_split.v"
    "${RTL_ROOT}/cmd/cmd_reorder_l1.v"
    "${RTL_ROOT}/cmd/cmd_reorder_l2.v"
    "${RTL_ROOT}/buffer/write_buffer.v"
    "${RTL_ROOT}/buffer/read_buffer.v"
    "${RTL_ROOT}/bank/bank_ctrl.v"
    "${RTL_ROOT}/bank/bank_ctrl_top.v"
    "${RTL_ROOT}/refresh/refresh_ctrl.v"
    "${RTL_ROOT}/init/init_fsm.v"
    "${RTL_ROOT}/dfi/dfi_if.v"
    "${RTL_ROOT}/ddr3_ctrl_top.v"
)

echo "=== Verilator Lint: DDR3 Controller ==="
echo "RTL root: ${RTL_ROOT}"
echo ""

ERRORS=0
for f in "${RTL_FILES[@]}"; do
    if [[ "${QUIET}" != "--quiet" ]]; then
        echo "  Linting: $(basename ${f})"
    fi
    if ! verilator --lint-only -Wall -Wno-STMTDLY \
        -I"${RTL_ROOT}" \
        --top-module "$(grep -m1 '^module ' ${f} | awk '{print $2}' | tr -d '(')" \
        "${f}" 2>&1; then
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""
if [[ ${ERRORS} -eq 0 ]]; then
    echo "=== LINT PASS: All ${#RTL_FILES[@]} modules clean ==="
else
    echo "=== LINT FAIL: ${ERRORS} module(s) with errors ==="
    exit 1
fi
