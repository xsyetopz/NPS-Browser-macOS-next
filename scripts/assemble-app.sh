#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/toolchain.sh"
BUILD_ROOT="$ROOT/.build"
ASSEMBLY_ROOT="$BUILD_ROOT/app-assembly"
APP="$BUILD_ROOT/app/NPS Browser.app"
ARCHES=(arm64 x86_64)
DEPLOYMENT_TARGET="$NPS_MACOS_DEPLOYMENT_TARGET"
RESOURCE_BUNDLE_STAGE="$ASSEMBLY_ROOT/resource-bundles"
RESOURCE_BUNDLE_ARM64_STAGE="$ASSEMBLY_ROOT/resource-bundles-arm64"
RESOURCE_BUNDLE_X86_64_STAGE="$ASSEMBLY_ROOT/resource-bundles-x86_64"

if [[ "$DEPLOYMENT_TARGET" != <->.<-> && "$DEPLOYMENT_TARGET" != <->.<->.<-> ]]; then
    print -u2 "NPS_MACOS_DEPLOYMENT_TARGET must be a dotted macOS version, not '$DEPLOYMENT_TARGET'."
    exit 2
fi

cd "$ROOT"
rm -rf "$ASSEMBLY_ROOT"
mkdir -p "$ASSEMBLY_ROOT" "$BUILD_ROOT/app"

swiftpm() {
    "$ROOT/scripts/swiftpm.sh" "$@"
}

verify_architectures() {
    local binary="$1"
    local found_architectures
    found_architectures="$(lipo -archs "$binary")"
    for required_architecture in arm64 x86_64; do
        if [[ " $found_architectures " != *" $required_architecture "* ]]; then
            print -u2 "Missing $required_architecture slice in $binary (found: $found_architectures)."
            exit 1
        fi
    done
}

for arch in $ARCHES; do
    triple="$arch-apple-macosx$DEPLOYMENT_TARGET"
    swiftpm build --configuration release --triple "$triple" --product NPSBrowserApp
    swiftpm build --configuration release --triple "$triple" --product Cpkg2zip
    bin_dir="$(swiftpm build --show-bin-path --configuration release --triple "$triple")"
    cp "$bin_dir/NPSBrowserApp" "$ASSEMBLY_ROOT/NPSBrowserApp-$arch"
    cp "$bin_dir/Cpkg2zip" "$ASSEMBLY_ROOT/Cpkg2zip-$arch"
    [[ -f "$bin_dir/libRealmSwift.dylib" ]] || {
        print -u2 "SwiftPM did not produce libRealmSwift.dylib for $arch."
        exit 1
    }
    cp "$bin_dir/libRealmSwift.dylib" "$ASSEMBLY_ROOT/libRealmSwift-$arch.dylib"

    resource_bundle_stage="$ASSEMBLY_ROOT/resource-bundles-$arch"
    mkdir -p "$resource_bundle_stage"
    bundle_count=0
    for resource_bundle in "$bin_dir"/*.bundle(N); do
        [[ -d "$resource_bundle" ]] || continue
        ditto "$resource_bundle" "$resource_bundle_stage/$(basename "$resource_bundle")"
        bundle_count=$((bundle_count + 1))
    done
    [[ "$bundle_count" -gt 0 ]] || {
        print -u2 "SwiftPM did not produce any resource bundles for $arch."
        exit 1
    }
done

bundle_names() {
    local directory="$1"
    local bundle
    for bundle in "$directory"/*.bundle(N); do
        print -r -- "${bundle:t}"
    done | LC_ALL=C sort
}

arm64_bundle_names="$(bundle_names "$RESOURCE_BUNDLE_ARM64_STAGE")"
x86_64_bundle_names="$(bundle_names "$RESOURCE_BUNDLE_X86_64_STAGE")"
if [[ "$arm64_bundle_names" != "$x86_64_bundle_names" ]]; then
    print -u2 "SwiftPM resource bundle sets differ between arm64 and x86_64 builds."
    print -u2 "arm64: $arm64_bundle_names"
    print -u2 "x86_64: $x86_64_bundle_names"
    exit 1
fi

mkdir -p "$RESOURCE_BUNDLE_STAGE"
for resource_bundle in "$RESOURCE_BUNDLE_ARM64_STAGE"/*.bundle(N); do
    ditto "$resource_bundle" "$RESOURCE_BUNDLE_STAGE/${resource_bundle:t}"
done

CONTENTS="$ASSEMBLY_ROOT/NPS Browser.app/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Helpers" "$CONTENTS/Frameworks"
lipo -create "$ASSEMBLY_ROOT/NPSBrowserApp-arm64" "$ASSEMBLY_ROOT/NPSBrowserApp-x86_64" -output "$CONTENTS/MacOS/NPSBrowserApp"
lipo -create "$ASSEMBLY_ROOT/Cpkg2zip-arm64" "$ASSEMBLY_ROOT/Cpkg2zip-x86_64" -output "$CONTENTS/Helpers/Cpkg2zip"
lipo -create "$ASSEMBLY_ROOT/libRealmSwift-arm64.dylib" "$ASSEMBLY_ROOT/libRealmSwift-x86_64.dylib" -output "$CONTENTS/Frameworks/libRealmSwift.dylib"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$CONTENTS/MacOS/NPSBrowserApp"
for resource_bundle in "$RESOURCE_BUNDLE_STAGE"/*.bundle(N); do
    [[ -d "$resource_bundle" ]] || continue
    ditto "$resource_bundle" "$CONTENTS/Resources/$(basename "$resource_bundle")"
done
cp "$ROOT/scripts/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $DEPLOYMENT_TARGET" "$CONTENTS/Info.plist"
cp "$ROOT/Sources/NPSBrowserAppResources/Resources/NPSBrowser.icns" "$CONTENTS/Resources/NPSBrowser.icns"
# Copy the NPSCore catalogs with their canonical tag casing so AppKit and
# CFBundleLocalizations see every shipped language.
localization_count=0
for localization in "$ROOT"/Sources/NPSCore/Resources/*.lproj(N); do
    ditto "$localization" "$CONTENTS/Resources/${localization:t}"
    localization_count=$((localization_count + 1))
done
[[ "$localization_count" -gt 0 ]] || {
    print -u2 "No NPSCore localizations found in Sources/NPSCore/Resources."
    exit 1
}
printf 'APPL????' > "$CONTENTS/PkgInfo"

if [[ -e "$APP" ]]; then
    rm -rf "$APP"
fi
mv "$ASSEMBLY_ROOT/NPS Browser.app" "$APP"

plutil -lint "$APP/Contents/Info.plist"
verify_architectures "$APP/Contents/MacOS/NPSBrowserApp"
verify_architectures "$APP/Contents/Helpers/Cpkg2zip"
verify_architectures "$APP/Contents/Frameworks/libRealmSwift.dylib"
for required_bundle in \
    NPSBrowser_NPSBrowserAppResources.bundle \
    NPSBrowser_NPSCore.bundle \
    RealmDatabase_RealmCoreResources.bundle \
    Realm_Realm.bundle \
    Realm_RealmSwift.bundle; do
    [[ -d "$APP/Contents/Resources/$required_bundle" ]] || {
        print -u2 "Missing required SwiftPM resource bundle: $required_bundle"
        exit 1
    }
done
print "Assembled universal app: $APP (minimum macOS $DEPLOYMENT_TARGET)"
