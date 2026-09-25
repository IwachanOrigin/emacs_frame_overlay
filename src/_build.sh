#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <emacs-include-dir>"
    echo
    echo "Example:"
    echo "  $0 /c/software/msys2/ucrt64/local/emacs/include"
    exit 1
fi

EMACS_INCLUDE_DIR="$1"

if [ ! -f "${EMACS_INCLUDE_DIR}/emacs-module.h" ]; then
    echo "Error: emacs-module.h was not found."
    echo "EMACS_INCLUDE_DIR=${EMACS_INCLUDE_DIR}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"

cmake \
    -S "${SCRIPT_DIR}" \
    -B "${BUILD_DIR}" \
    -G "MinGW Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DEMACS_INCLUDE_DIR="${EMACS_INCLUDE_DIR}"

cmake --build "${BUILD_DIR}"

