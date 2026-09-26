# Localization

Use this procedure to update one shipped language without changing keys or
runtime identifiers.

One Foundation catalog in `NPSCore`. The macOS preferred-language order picks
the language. There is no in-app switcher.

## Files

- `Sources/NPSCore/Resources/Localization/Localizable.template.strings`
- `Sources/NPSCore/Resources/Localization/Localizable.template.stringsdict`
- Shipped languages: `Sources/NPSCore/Resources/<tag>.lproj/`, each with
  `Localizable.strings` and `Localizable.stringsdict`

`Package.swift` sets `defaultLocalization: "en-US"`. `scripts/assemble-app.sh`
copies every NPSCore `<tag>.lproj` into the app, and `scripts/Info.plist` lists
the tags in `CFBundleLocalizations`. `NPSCore.Localization` resolves strings and
plurals; the app calls it through `AppResources.localized(_:)` and
`AppResources.plural(_:count:)`.

## Tags

Language-region tags, with no `Base`, `zh-Hans` or `zh-Hant`:
`C`, `en-US`, `en-GB`, `da-DK`, `de-DE`, `es-ES`, `fr-FR`, `it-IT`, `nl-NL`,
`nb-NO`, `pt-BR`, `pt-PT`, `ru-RU`, `fi-FI`, `pl-PL`, `sv-SE`, `tr-TR`, `ja-JP`,
`ko-KR`, `zh-CN`, `zh-TW` (the 20 PS3 system languages plus the POSIX `C`
source).

- `C` and `en-US` hold the same American-English source as the template.
- `en-GB` uses British spelling (catalogue, colour).
- Do not add tags without updating `scripts/Info.plist`,
  `scripts/verify-app-bundle.sh` and the localization tests.

## Fallback

`Bundle.preferredLocalizations` maps the user's languages to a tag, for example
`zh-Hans-CN` to `zh-CN`, `zh-Hant-TW` and `zh-HK` to `zh-TW`, `nb` and `no` to
`nb-NO`, `pt` to `pt-BR`, `en-AU` to `en-GB`, and an unknown language to
`en-US`. A key missing from the selected catalog falls back to source English
(`en-US`), then to the caller's default value.

## Punctuation

- English source: Unicode ellipsis `…` on commands that open another surface,
  and curly `’`.
- Translations: native punctuation and quotes (`„…“`, `«…»`, `「…」`).
- No ASCII `"` inside a `.strings` value.

## Translate

1. Copy the template key shape into the target `.lproj` pair.
1. Translate the values. Keep keys, placeholders (`%@`, `%d`, `%1$@`,
   `%#@count@`) and runtime identifiers (URLs, file names, title IDs).
1. Counts live only in `.stringsdict`. Give each plural the CLDR categories
   Foundation uses for the language (for example `one`/`other` in English,
   `one`/`few`/`many`/`other` in Russian and Polish, `other` in Japanese,
   Korean and Chinese). Never branch on `count == 1` in code.
1. Leave brand and technical tokens such as NPS Browser, PlayStation, PS Vita,
   PSP, PKG, RAP, zRIF, URL, ZIP and ISO untranslated.

Put the language first in macOS System Settings to try it.

## Runtime and tests

Code renders text through `Localization.current`: the task-local
`Localization.override` when set, otherwise `Localization.shared` (the system
language order). Setting `NPS_PREFERRED_LANGUAGES` (for example `zh-CN` or
`ja-JP,en-US`) replaces the system order for `shared`, without `defaults write`.

Errors and persisted download messages carry `LocalizedMessage` values (catalog
key plus typed arguments) and are rendered only when shown, so they follow the
current language and compare equal in every language.

Every test suite and free `@Test` carries the `.sourceEnglish` trait
(`Tests/<Target>Tests/Support/SourceEnglishTrait.swift`), which binds the
override to `en-US`; `scripts/check-structure.sh` enforces it. To check that
tests do not depend on the Mac's language:

```bash
NPS_PREFERRED_LANGUAGES=zh-CN swift test
```

```bash
export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
swift test --filter NPSCoreTests.Localization
```
