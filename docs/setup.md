# Build and release setup

## Requirements

- An Xcode with an Apple Swift 6.1 or later toolchain, selected with
  `DEVELOPER_DIR`. Xcode 26.6 ships Apple Swift 6.3.3, the version
  `.swift-version` names, and is the local default. Realm's C++ targets
  (realm-core) build only with Apple's clang; swiftly's open-source 6.3.3 fails
  on realm-core's module maps, and the scripts refuse a non-Apple Swift with
  that explanation.
- `just` and SwiftLint (`brew install just swiftlint`). swift-format ships with
  the Swift toolchain.
- Network access the first time SwiftPM resolves the pinned RealmSwift package.

`Package.swift` requires Swift tools 6.1 and sets Swift language mode 6. It
selects RealmSwift 20.0.3 with Swift 6.1 and RealmSwift 20.0.5 with Swift 6.3
or later. Realm 20.0.3's release notes include the Xcode 16.4 build, while
20.0.5's release notes cover Xcode 27 compatibility ([20.0.3](https://github.com/realm/realm-swift/releases/tag/v20.0.3),
[20.0.5](https://github.com/realm/realm-swift/releases/tag/v20.0.5)).
`Package.resolved` pins RealmSwift 20.0.5 and Realm Core 20.1.5; Swift 6.1
resolves the manifest's exact 20.0.3 requirement instead.

SwiftPM is the only build system. There is no Xcode project, Carthage, or
`xcodebuild` workflow.

## Toolchain selection

Every recipe goes through `scripts/toolchain.sh`, which:

1. Runs `xcrun swift` from `DEVELOPER_DIR` when it is set. A `TOOLCHAINS`
   value exported by swiftly (`org.swift.*`) is ignored in that case, so xcrun
   uses the Xcode's default toolchain.
1. Refuses a non-Apple Swift, because realm-core cannot be built with it.
1. Sets `NPS_MACOS_DEPLOYMENT_TARGET` to 10.15 when it is unset. If the Xcode's
   SDK cannot target 10.15, the value rises to the SDK's minimum and the bundle
   check prints a note.

Xcode 26.6 (Swift 6.3.3, macOS 26.5 SDK) and Xcode 16.3 (Swift 6.1, macOS 15.4
SDK) both build and check the real 10.15 bundle on this machine. Xcode 27 cannot:
its SDK and SwiftPM's swiftbuild engine reject targets below 12.0, and even with
an older SDK its linker writes `minos 12.0` into every slice. With Xcode 27 the
target rises to 12.0 and the bundle check prints a note.

`scripts/swiftpm.sh` builds each Swift version in its own
`.build/swift-<version>` directory, because modules built by one compiler cannot
be imported by another. The assembled app always goes to
`.build/app/NPS Browser.app`.

Xcode 16.3's AddressSanitizer runtime deadlocks during start-up on macOS 27
(it spins in `AsanInitInternal` before `main`). The pkg2zip name-bounds probe
test therefore runs its ASan build with a 30-second limit and, if that build
never starts, repeats the bounds check uninstrumented; a real hang in pkg2zip
still fails the test. Swift 6.1 also re-resolves RealmSwift to 20.0.3, which
rewrites `Package.resolved`; restore it before committing.

## Commands

```sh
just build    # SwiftPM debug build
just test     # Swift Testing suites
just lint     # layout rules, swift format lint --strict, swiftlint lint --strict
just format   # swift format --in-place (SwiftLint autocorrect is not used)
just app      # release slices and .app assembly
just verify   # lint, tests, app assembly, bundle checks
```

The app assembly script builds the app and `Cpkg2zip` helper separately for
`arm64-apple-macosx<target>` and `x86_64-apple-macosx<target>`. It then
combines the slices with `lipo` and adds the package resource bundles, the app
icon, and the 21 NPSCore localizations (see [`LOCALIZATION.md`](../LOCALIZATION.md)).
It sets `LSMinimumSystemVersion` to the target and declares the localizations in
`CFBundleLocalizations`. The output is
`.build/app/NPS Browser.app`.

The bundle check requires:

- a matching `LSMinimumSystemVersion`;
- arm64 and x86_64 slices in the app, `Cpkg2zip`, and Realm;
- all expected SwiftPM resource bundles;
- the legacy bundle identifier and the scoped ATS exceptions;
- Mach-O minimum versions no higher than the target for Intel, and no higher
  than 11.0 for Apple Silicon (arm64 cannot declare a lower minimum).

## Project layout

The app follows Cocoa MVC, AppKit's own pattern, with I/O kept out of
controllers:

- `Sources/NPSBrowserApp/App/`: the entry point, `AppDelegate`, and the main
  menu.
- `Controllers/`: window and view controllers. They coordinate views and call
  services; they do no networking, parsing, file I/O, or persistence.
- `Views/`: `NSView` code, cell builders, and symbol drawing.
- `Models/`: value types and pure logic (sections, entries, filtering, counts).
- `Services/`: the `BrowserDataSource` protocol and its implementations,
  catalogue loading, workspace notifications, and stored interface preferences.

The library targets group files by concern, for example
`NPSDownloads/Coordinator/`, `Transfer/`, `Integrity/`, `Extraction/`, and
`Migration/`, and `NPSCore/Catalogue/`, `Settings/`, and `Models/`. A type that
covers several concerns is split into `<Type>+<Concern>.swift` extension files.

`scripts/check-structure.sh` runs as part of `just lint` and fails when:

- a Swift source file exceeds 350 lines, or a test file exceeds 1000 lines;
- a test file outside `Support/` and `Fixtures/` is not named
  `<Stem>Tests.swift` or `<Stem>Tests+<Part>.swift`, or has no
  `Sources/<Target>/<same directory>/<Stem>.swift`.

Shared test fakes and helpers live in `Tests/<Target>Tests/Support/`.

## GitHub Actions verification

`.github/workflows/verify.yml` runs an unprivileged Intel `macos-15-intel` job.
It:

1. selects `/Applications/Xcode_16.4.app`;
1. verifies Xcode 16.4, Swift 6.1, and the macOS 15.5 SDK;
1. installs `just` and SwiftLint;
1. runs `just verify` with `NPS_MACOS_DEPLOYMENT_TARGET=10.15`.

Checkout uses a full SHA and does not persist credentials. The workflow does not
upload, publish, sign, or notarize anything. It has not run on GitHub yet, so
there is no hosted result to cite.

## Verification record

On 2026-09-25, on macOS 27 arm64, `just verify` exited 0 with each of:

- `DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer`
  (Apple Swift 6.3.3, macOS 26.5 SDK);
- `DEVELOPER_DIR=/Applications/Xcode-16.3.0.app/Contents/Developer`
  (Apple Swift 6.1, macOS 15.4 SDK, RealmSwift 20.0.3).

Each run covered:

- **Lint:** `swift format lint --strict` and `swiftlint lint --strict` were clean.
- **Tests:** 152 Swift Testing tests passed: 5 persistence, 49 downloads,
  29 core and settings, 69 app.
- **App:** the universal app, `Cpkg2zip` helper, and Realm were assembled at a
  macOS 10.15 minimum.
- **Bundle:** the check passed. x86_64 slices declare 10.15 (Realm's declares
  10.13), and arm64 slices declare 11.0.

Xcode 27 (Swift 6.4) also passes with a 12.0 bundle, because it cannot target
10.15.

Checks added in this pass, each confirmed to fail when its fix is removed:

- **Quit during pack verification:** `quitting while a pack verifies does not
  start its patch download`. The earlier queued-job case is covered by
  `shutdown pauses active work without starting queued jobs`.
- **Stale Reveal on Downloads re-entry:**
  `reenteringDownloadsWithholdsCachedRevealUntilTheFreshSnapshot`.
- **Pending-row duplicate:**
  `requestedJobInSnapshotReplacesItsPlaceholderBeforeEnqueueReturns`, plus
  `a caller-chosen job ID is published before enqueue returns; duplicates keep
  the original ID`.
- **Pending-row gap:** `placeholderStaysVisibleUntilThePostEnqueueSnapshotArrives`.
- **Update and package download of one entry at once:**
  `packageDownloadIsQueuedWhileAnUpdateLookupForTheSameEntryIsPending`.

Not verified here:

- The CI workflow itself. It has not run on GitHub yet.
- A launch on macOS 10.15. No Catalina host or VM is available.
- A launch of the assembled app on any system.
- Physical VoiceOver or Finder interaction.
- Real game packages or live Sony endpoints.
- Signing and notarization.

`.swift-version` names 6.3.3. Swiftly's open-source 6.3.3 cannot build
realm-core, so local builds use Xcode 26.6's Apple Swift 6.3.3.

## Data upgrade

Before the first app release that opens an existing Realm database, make a
recoverable copy of the user's database and verify its migration path. The
application must not delete a source database if migration fails. Do not use a
working user database as a migration test fixture.

Before opening Realm, the app imports the archived `downloads` binary plist from
the existing UserDefaults domain into the native `downloads.plist` queue. It
backs up the raw plist under `Application Support/NPS Browser/LegacyDownloadBackups/`
but leaves the UserDefaults value untouched. The archived app can write that key
concurrently, and deleting it could remove newer data. The app records the
SHA-256 digest of each imported archive in a sidecar only after the native queue
has been atomically saved. An unchanged archive is not re-imported, so removing
an imported job does not resurrect it on relaunch. Changed archive bytes are
backed up and merged as a new import. Stable migration IDs and destination
comparisons make retry safe if saving the digest fails after the queue save. A
decode or validation failure stops startup with an error; the original defaults
value remains available and no partial jobs are written.

Legacy completed entries keep their recorded destinations and remain revealable
when the file still exists. They remain marked unverified because the archived
app did not persist the new integrity result. Interrupted entries are never
started during migration: nonempty saved resume data is offered as a paused
transfer, while entries without it are marked failed with a restart instruction.
The resume data is opaque, so URLSession can still reject it when the user asks
to resume. A subsequent restart reserves a fresh collision-safe filename and
does not replace the archived destination.

For a legacy `Extraction Complete` PSV Game, DLC, or Update, the app derives the
old output location under the recorded destination's console directory:
`app/<titleID>`, `addcont/<titleID>`, or `patch/<titleID>`. This matches the
archived `DownloadListItemCellView.viewFile()` routes. It retains that exact
directory path even when it is currently unavailable and checks it dynamically.
If the folder is missing, the job stays complete and asks the user to reconnect
the original volume. While Downloads is visible, the app listens for
`NSWorkspace` mount/unmount notifications and reloads the queue snapshot to
update Reveal. Fixture checks cover mount/unmount, out-of-order snapshots,
buffered stream events, and selection/pending-row preservation. These checks use
an injected notification center and temporary paths; they do not verify a
physical volume notification or Finder reveal. On Downloads view re-entry, cached
rows withhold Reveal until the fresh snapshot confirms each file
(`reenteringDownloadsWithholdsCachedRevealUntilTheFreshSnapshot`). If the old output location cannot be derived, the job reports
`legacy-output-location-unknown` and never reveals the recorded PKG as extracted
content. Other legacy extraction layouts remain unverified.

The old CPack→CPatch workflow cannot be guaranteed from archived downloads. The
old `DetailsViewController` linked a pack's `doNext` patch item and also linked
that patch's `parentItem` back to the pack (`NPS Browser/controllers/DetailsViewController.swift`,
lines 68–69). `DLItem.CodingKeys` encodes both links, and
`DownloadManager.stopAndStoreDownloadList()` encodes `DownloadList` using
synthesized `Codable` (`NPS Browser/services/DownloadManager.swift`, lines
102–120). The reciprocal object cycle has no reference identity in a property
list; recursive value encoding cannot represent it. The archived save catches
encoding failure and leaves the previous defaults value. No CPack/CPatch pair
import is claimed or verified.

The app bundle keeps the archived identifier `JK3Y.NPS-Browser`. `SettingsStore`
reads the corresponding standard UserDefaults domain, so changing the bundle
identifier would hide saved catalogue URLs, download destinations, concurrency,
and extraction settings from an existing installation. Bundle verification
checks this identifier.

## Catalogue and download behavior

The default catalogue has 11 HTTPS NoPayStation TSV feeds: PS Vita Games,
Add-ons, and Themes; PSP Games and Add-ons; PlayStation Games; PS3 Games,
Add-ons, Themes, and Avatars; and PlayStation Mobile Games. The added defaults
are `https://nopaystation.com/tsv/PSM_GAMES.tsv` and
`https://nopaystation.com/tsv/PSP_DLCS.tsv`. Both appear in the Preferences
catalogue-source picker. PSM Games also has a PlayStation Mobile sidebar
section; PSP DLC rows use the existing PSP section. The parser reads the
published positional columns for both feeds, including PSM zRIF and PSP DLC RAP
fields. Saving a catalogue URL change reloads the catalogue without restarting
the app. The existing Vita update HMAC URL builder and CompatPack/CompatPatch
defaults are unchanged.

The output-folder preference edits the effective package destination stored in
the legacy `dl_library_folder` key. The coordinator snapshots that folder when
it creates a job, so changing the preference affects new jobs and leaves
already-persisted destinations unchanged. The “Hide items without a valid
package URL” preference controls whether catalogue records with missing links
remain visible.

The bundled `Cpkg2zip` helper is built from the native package target for Intel
and Apple Silicon; the archived Windows executable is not used. The destination
picker remains user-controlled, and new jobs use its saved location without an
app restart.

Compatibility-pack entries use the saved extraction preference. Selecting a
CPatch with a matching CPack queues the pack and patch together. A patch with no
matching pack queues its `.ppk` archive alone; when extraction is enabled, the
patch is safely overlaid on the existing title-ID output, and when extraction
is disabled, the verified archive is kept without changing that output. Unsafe
archives or an unsafe existing output fail without replacing the prior files;
local fixture tests cover these paths, not real game packages.

The Updates section lists PS Vita game entries that can be checked. The app
constructs the legacy update metadata URL in Swift, fetches its XML, parses the
latest package URL, and queues that package as an update. The URL's
HMAC-SHA256 scheme follows the public
[vitanpupdatelinks implementation](https://github.com/devnoname120/vitanpupdatelinks)
(credited there to Proxima); `PCSA00007` has the documented digest
`86d7c3b64d554b9639c5ad69aac20e16ea34c2f513d412f38329257f4ad15782`.

The legacy PS Vita update metadata host currently requires HTTP because its TLS
certificate fails validation. `NSAppTransportSecurity` therefore has a
host-specific exception for `gs-sec.ww.np.dl.playstation.net`, alongside the
existing narrowly scoped package-host exceptions for `ares.dl.playstation.net`
and `zeus.dl.playstation.net`. No global arbitrary-load exception is enabled.

Bookmark export reads every persisted Realm bookmark rather than the visible
catalogue subset, so records whose catalogue rows disappeared are included.

## Distribution

Signing and notarization are intentionally not configured. Supply the required
identity and authorization through a separately approved distribution setup;
do not put credentials in the package, scripts, or repository.
