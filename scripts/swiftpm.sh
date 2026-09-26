#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/toolchain.sh"

# Modules built by one Swift version cannot be imported by another, so each
# toolchain gets its own build directory when switching Xcodes.
if [[ "${1:-}" == build || "${1:-}" == test || "${1:-}" == run ]]; then
    set -- "$1" --scratch-path "$ROOT/.build/swift-$NPS_SWIFT_BUILD_ID" "${@:2}"
fi
nps_swift "$@"
