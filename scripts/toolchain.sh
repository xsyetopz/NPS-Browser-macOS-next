#!/bin/zsh
# Sourced by the other scripts. Selects the Swift driver and exports
# NPS_MACOS_DEPLOYMENT_TARGET.

NPS_MINIMUM_MACOS="10.15"

# swiftly exports TOOLCHAINS for its own proxy, so only an explicit
# DEVELOPER_DIR selects an Xcode toolchain through xcrun, and then that Xcode's
# default toolchain rather than the swiftly one TOOLCHAINS names.
if [[ -n "${DEVELOPER_DIR:-}" && "${TOOLCHAINS:-}" != com.apple.* ]]; then
    unset TOOLCHAINS
fi

nps_swift() {
    if [[ -n "${DEVELOPER_DIR:-}" ]]; then
        xcrun swift "$@"
    else
        swift "$@"
    fi
}

# Succeeds when dotted version $1 <= $2.
nps_version_le() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        split(a, x, "."); split(b, y, ".")
        for (i = 1; i <= 3; i++) {
            if ((x[i] + 0) < (y[i] + 0)) exit 0
            if ((x[i] + 0) > (y[i] + 0)) exit 1
        }
        exit 0
    }'
}

# Realm's C++ targets build only with Apple's clang; open-source toolchains
# (such as swiftly's) fail on realm-core's module maps.
nps_require_apple_swift() {
    local version
    version="$(nps_swift --version 2>/dev/null || true)"
    if [[ "$version" != *swiftlang-* ]]; then
        print -u2 "The active Swift is not an Apple toolchain; realm-core needs Apple clang."
        print -u2 "Set DEVELOPER_DIR to an Xcode, e.g. DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer just verify"
        exit 1
    fi
    NPS_SWIFT_BUILD_ID="${${version#*\(swiftlang-}%% *}"
}

# Defaults to the project floor, raised to the SDK's minimum when the Xcode
# cannot target the floor. Borrowing an older SDK does not help: the Xcode's
# linker still stamps its own minimum (Xcode 27 writes 12.0) into every binary.
nps_select_deployment_target() {
    [[ -z "${NPS_MACOS_DEPLOYMENT_TARGET:-}" ]] || return 0
    local sdk sdk_minimum
    sdk="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
    sdk_minimum="$(plutil -extract SupportedTargets.macosx.MinimumDeploymentTarget raw "$sdk/SDKSettings.plist" 2>/dev/null || true)"
    if [[ -n "$sdk_minimum" ]] && ! nps_version_le "$sdk_minimum" "$NPS_MINIMUM_MACOS"; then
        export NPS_MACOS_DEPLOYMENT_TARGET="$sdk_minimum"
    else
        export NPS_MACOS_DEPLOYMENT_TARGET="$NPS_MINIMUM_MACOS"
    fi
}

nps_require_apple_swift
nps_select_deployment_target
