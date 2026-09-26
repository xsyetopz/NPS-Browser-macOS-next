#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/app/NPS Browser.app"
CONTENTS="$APP/Contents"
PLIST="$CONTENTS/Info.plist"
source "$ROOT/scripts/toolchain.sh"
EXPECTED_MINIMUM="$NPS_MACOS_DEPLOYMENT_TARGET"
# Apple Silicon slices cannot declare a minimum below macOS 11.0.
ARM64_PLATFORM_MINIMUM="11.0"
if ! nps_version_le "$EXPECTED_MINIMUM" "$ARM64_PLATFORM_MINIMUM"; then
    ARM64_PLATFORM_MINIMUM="$EXPECTED_MINIMUM"
fi
if [[ "$EXPECTED_MINIMUM" != "$NPS_MINIMUM_MACOS" ]]; then
    print -u2 "Note: verifying a macOS $EXPECTED_MINIMUM bundle; the selected Xcode cannot target the project floor $NPS_MINIMUM_MACOS (CI builds that floor)."
fi

[[ -x "$CONTENTS/MacOS/NPSBrowserApp" ]]
[[ -x "$CONTENTS/Helpers/Cpkg2zip" ]]
[[ -f "$CONTENTS/Frameworks/libRealmSwift.dylib" ]]
[[ -f "$CONTENTS/Resources/NPSBrowser.icns" ]]
plutil -lint "$PLIST"

# NPSCore owns the catalogs; the app bundle carries every tag it declares.
expected_localizations=(C en-US en-GB da-DK de-DE es-ES fr-FR it-IT nl-NL nb-NO pt-BR pt-PT ru-RU fi-FI pl-PL sv-SE tr-TR ja-JP ko-KR zh-CN zh-TW)
development_region="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDevelopmentRegion' "$PLIST")"
[[ "$development_region" == "en-US" ]] || { print -u2 "Expected CFBundleDevelopmentRegion en-US; got $development_region"; exit 1; }
declared_localizations="$(plutil -extract CFBundleLocalizations json -o - "$PLIST" | tr -d '[]"' | tr ',' '\n' | LC_ALL=C sort)"
[[ "$declared_localizations" == "$(print -l -- $expected_localizations | LC_ALL=C sort)" ]] || {
    print -u2 "CFBundleLocalizations does not match the supported tags: $declared_localizations"
    exit 1
}
packaged_localizations="$(for directory in "$CONTENTS"/Resources/*.lproj(N); do print -r -- "${directory:t:r}"; done | LC_ALL=C sort)"
[[ "$packaged_localizations" == "$(print -l -- $expected_localizations | LC_ALL=C sort)" ]] || {
    print -u2 "Contents/Resources localizations do not match the supported tags: $packaged_localizations"
    exit 1
}
for localization in $expected_localizations; do
    for table in Localizable.strings Localizable.stringsdict; do
        plutil -lint -s "$CONTENTS/Resources/$localization.lproj/$table" || {
            print -u2 "Missing or invalid $localization.lproj/$table"
            exit 1
        }
    done
done

bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
[[ "$bundle_identifier" == "JK3Y.NPS-Browser" ]] || { print -u2 "Expected legacy defaults domain JK3Y.NPS-Browser; got $bundle_identifier"; exit 1; }
minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")"
[[ "$minimum" == "$EXPECTED_MINIMUM" ]] || { print -u2 "Expected macOS $EXPECTED_MINIMUM minimum; got $minimum"; exit 1; }

for domain in gs-sec.ww.np.dl.playstation.net ares.dl.playstation.net zeus.dl.playstation.net; do
    exception="$(/usr/libexec/PlistBuddy -c "Print :NSAppTransportSecurity:NSExceptionDomains:$domain:NSExceptionAllowsInsecureHTTPLoads" "$PLIST")"
    [[ "$exception" == "true" ]] || { print -u2 "Missing scoped HTTP exception for $domain"; exit 1; }
done
if /usr/libexec/PlistBuddy -c 'Print :NSAppTransportSecurity:NSAllowsArbitraryLoads' "$PLIST" >/dev/null 2>&1; then
    print -u2 "Global arbitrary network loads must remain disabled."
    exit 1
fi

for required_bundle in \
    NPSBrowser_NPSBrowserAppResources.bundle \
    NPSBrowser_NPSCore.bundle \
    RealmDatabase_RealmCoreResources.bundle \
    Realm_Realm.bundle \
    Realm_RealmSwift.bundle; do
    [[ -d "$CONTENTS/Resources/$required_bundle" ]] || {
        print -u2 "Missing required SwiftPM resource bundle: $required_bundle"
        exit 1
    }
done

verify_universal_binary() {
    local binary="$1"
    local architectures
    architectures="$(lipo -archs "$binary")"
    for architecture in arm64 x86_64; do
        [[ " $architectures " == *" $architecture "* ]] || {
            print -u2 "Missing $architecture slice in $binary (found: $architectures)."
            exit 1
        }
    done
}

verify_macho_minimum_version() {
    local binary="$1"
    local architecture load_commands actual_version expected_architecture_minimum
    for architecture in arm64 x86_64; do
        expected_architecture_minimum="$EXPECTED_MINIMUM"
        if [[ "$architecture" == "arm64" ]]; then
            expected_architecture_minimum="$ARM64_PLATFORM_MINIMUM"
        fi
        load_commands="$(otool -l -arch "$architecture" "$binary")"
        actual_version="$(print -r -- "$load_commands" | awk '
            $1 == "cmd" && $2 == "LC_BUILD_VERSION" { command = "build"; next }
            $1 == "cmd" && $2 == "LC_VERSION_MIN_MACOSX" { command = "legacy"; next }
            command == "build" && $1 == "minos" { print $2; exit }
            command == "legacy" && $1 == "version" { print $2; exit }
        ')"
        if [[ -z "$actual_version" || ( "$actual_version" != <->.<-> && "$actual_version" != <->.<->.<-> ) ]]; then
            print -u2 "Could not read a macOS minimum from $binary ($architecture)."
            exit 1
        fi
        if ! awk -F. -v actual="$actual_version" -v expected="$expected_architecture_minimum" 'BEGIN {
            split(actual, actual_parts, ".")
            split(expected, expected_parts, ".")
            for (part = 1; part <= 3; part++) {
                actual_part = actual_parts[part] + 0
                expected_part = expected_parts[part] + 0
                if (actual_part < expected_part) exit 0
                if (actual_part > expected_part) exit 1
            }
            exit 0
        }'; then
            print -u2 "$binary ($architecture) requires macOS $actual_version, above the $architecture platform floor $expected_architecture_minimum."
            exit 1
        fi
    done
}

for binary in \
    "$CONTENTS/MacOS/NPSBrowserApp" \
    "$CONTENTS/Helpers/Cpkg2zip" \
    "$CONTENTS/Frameworks/libRealmSwift.dylib"; do
    verify_universal_binary "$binary"
    verify_macho_minimum_version "$binary"
done

print "Verified macOS $EXPECTED_MINIMUM plist floor, ${#expected_localizations} localizations, universal app/helper/Realm slices, SwiftPM resources and Mach-O minimum versions."
