# NPS Browser for macOS

NPS Browser is a native macOS catalogue browser for NoPayStation content. It is
implemented with AppKit and Swift 6. The package declares a macOS 10.15
deployment floor and builds universal Intel and Apple Silicon app slices when
used with a toolchain that supports that deployment target.

The replacement uses Swift Package Manager as its only build definition. It has
separate core, persistence, download, extraction-helper, and AppKit application
targets. It does not require the archived Xcode project or Carthage workflow.

The native catalogue includes game-update lookup for PS Vita titles, bookmarks
and complete persisted-bookmark CSV export, and a Downloads activity view. The
download preference points to the effective package output folder; new jobs use
the saved destination immediately, while existing jobs keep their recorded
destination. Saving a catalogue-source change reloads the catalogue without an
app restart.

The default sources include 11 HTTPS NoPayStation TSV feeds, including the PSM
Games and PSP DLC feeds. PSM Games has its own sidebar section, and PSP DLC
items appear with PSP content. Both feed URLs are editable in Preferences. The
existing Vita update HMAC URL builder and CompatPack/CompatPatch feed defaults
remain in place. Extraction uses the native `Cpkg2zip` helper built by SwiftPM,
not the archived Windows executable.

## Build and test

`Package.swift` is the only build definition. It requires Swift tools 6.1 and
Swift language mode 6, and declares a macOS 10.15 deployment floor. Install
`just`, SwiftLint, and an Xcode, then run:

```sh
export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
just build    # swift build
just test     # Swift Testing suites
just lint     # layout rules, swift-format and SwiftLint
just format   # rewrite sources with swift-format
just app      # universal .build/app/NPS Browser.app
just verify   # lint, test, app, bundle checks
```

Toolchain policy:

- **Floor:** Swift tools 6.1. Xcode 16.3 checks it locally. CI checks it with
  Xcode 16.4 (Swift 6.1, macOS 15.5 SDK) on an Intel `macos-15-intel` runner,
  which pins `NPS_MACOS_DEPLOYMENT_TARGET=10.15`.
- **Local:** `.swift-version` names Swift 6.3.3; use it through Xcode 26.6,
  which ships Apple Swift 6.3.3. realm-core compiles only with Apple's clang, so
  swiftly's open-source 6.3.3 cannot build the package, and the scripts stop
  with an explanation when the active Swift is not an Apple toolchain.
- **Deployment target:** `scripts/toolchain.sh` uses 10.15 unless the selected
  Xcode cannot target it, and then it uses that Xcode's minimum and says so.
  Xcode 26.6 and 16.3 build and check the real 10.15 bundle locally. Xcode 27's
  SDK and linker start at macOS 12.0, so with it `just verify` checks a 12.0
  bundle.
- **Build folders:** each Swift version builds in its own
  `.build/swift-<version>`, so switching Xcodes does not mix modules.

See [setup and release notes](docs/setup.md) for the verification record and
the checks that still need hardware this environment lacks: a macOS 10.15 host,
physical VoiceOver and Finder use, and real game packages.

No signing or notarization credentials are stored in this repository. The
assembled app is an unsigned local build.

## Languages

The interface is localized into the 20 PlayStation 3 system languages, with
language-region catalogs (`en-US`, `de-DE`, `ja-JP`, `zh-CN`, `zh-TW`, …) and a
POSIX `C` source catalog. macOS picks the language from your preferred-language
order. See [LOCALIZATION.md](LOCALIZATION.md) to update a translation.

## Upstream record

The dated local export of upstream issues, pull requests, comments, reviews,
and patches is in [`docs/upstream/`](docs/upstream/). Its disposition table is
an evidence tracker only; it does not change upstream GitHub state.

## License

See [LICENSE.md](LICENSE.md).
