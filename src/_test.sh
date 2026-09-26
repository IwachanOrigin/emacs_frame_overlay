#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

EMACS="${1:-emacs}"

if ! command -v "${EMACS}" >/dev/null 2>&1 && [ ! -x "${EMACS}" ]; then
    echo "Error: Emacs executable was not found."
    echo
    echo "Usage:"
    echo "  $0 [emacs-executable]"
    echo
    echo "Example:"
    echo "  $0 /c/software/msys2/ucrt64/local/emacs/bin/emacs.exe"
    exit 1
fi

echo "Running frame-overlay ERT tests..."
echo

"${EMACS}" \
    -Q \
    --batch \
    -L "${SCRIPT_DIR}/main/emacs" \
    -L "${SCRIPT_DIR}/test/emacs" \
    -l "${SCRIPT_DIR}/test/emacs/frame-overlay-test.el" \
    -f ert-run-tests-batch-and-exit

