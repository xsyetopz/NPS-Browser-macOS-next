#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/toolchain.sh"

PATHS=(Package.swift Sources Tests)

# SwiftLint needs sourcekitd; without an Xcode.app it must come from the
# active toolchain.
if [[ -z "${TOOLCHAIN_DIR:-}" ]]; then
    if [[ -n "${DEVELOPER_DIR:-}" ]]; then
        export TOOLCHAIN_DIR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain"
    elif toolchain="$(swiftly use --print-location 2>/dev/null | tail -1)" && [[ -d "$toolchain" ]]; then
        export TOOLCHAIN_DIR="$toolchain"
    fi
fi

if [[ "${1:-}" == "--fix" ]]; then
    nps_swift format format --in-place --recursive --parallel "${PATHS[@]}"
    exit 0
fi

"$ROOT/scripts/check-structure.sh"
"$ROOT/scripts/check-strings.sh"
nps_swift format lint --strict --recursive --parallel "${PATHS[@]}"
swiftlint lint --strict --quiet "${PATHS[@]}"
