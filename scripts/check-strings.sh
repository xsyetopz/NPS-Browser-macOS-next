#!/bin/zsh
# Fails on user-facing string literals in Sources/: every piece of UI text,
# accessibility text, alert text and error message must come from the NPSCore
# catalog (`Localization` in libraries, `AppResources.localized` in the app).
#
# A literal is flagged when, after removing `\(...)` interpolations and format
# specifiers, it
#   - reads as prose: two words of two or more letters separated by a space, or
#   - sits on a line that sets UI text (alert buttons and text, titles, labels,
#     tooltips, accessibility, placeholders), whatever its shape.
# Not flagged: `//` comment lines, raw `#"…"#` strings (regular expressions),
# and dotted catalog keys or SF Symbol names such as `settings.form.url`.
#
# Allowlist. Keep it small; each entry must be a runtime identifier, never
# text a user reads.
#   IDENTIFIER_CONTEXTS: the literal is an argument that names something on disk,
#     in defaults, in a feed or in the process (paths, keys, identifiers,
#     selectors, queue labels, locale identifiers, crash messages).
#   IDENTIFIER_LITERALS: exact literals, each scoped to the one file that owns
#     it, for feed or legacy data tokens split over several lines so no call
#     context sits beside them.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

IDENTIFIER_CONTEXTS=(
    'appendingPathComponent\('       # file and folder names
    'forKey:'                        # UserDefaults keys
    'Identifier\('                   # toolbar, column, item identifiers
    'Selector\('                     # Objective-C selectors
    'fatalError\('                   # programmer errors, never shown
    'DispatchQueue\(label:'          # queue labels
    'dateFormat ='                   # date format patterns
    'hasPrefix\('                    # content sniffing and prefix matching
)

IDENTIFIER_LITERALS=(
    # "<file glob>|<exact literal>": each literal is allowed only in the file that owns it.
    # NoPayStation TSV header names and missing-value markers.
    'Sources/NPSCore/Catalogue/CatalogParser*.swift|Title ID'
    'Sources/NPSCore/Catalogue/CatalogParser*.swift|PKG direct link'
    'Sources/NPSCore/Catalogue/CatalogParser*.swift|Content ID'
    'Sources/NPSCore/Catalogue/CatalogParser*.swift|Last Modification Date'
    'Sources/NPSCore/Catalogue/CatalogParser*.swift|Original Name'
    'Sources/NPSCore/Catalogue/CatalogParser*.swift|File Size'
    'Sources/NPSCore/Catalogue/CatalogParser*.swift|Required FW'
    'Sources/NPSCore/Catalogue/CatalogParser*.swift|Download .RAP file'
    'Sources/NPSCore/Catalogue/CatalogParser*.swift|CART ONLY'
    'Sources/NPSCore/Catalogue/CatalogParser*.swift|NOT REQUIRED'
    'Sources/NPSCore/Catalogue/CatalogParser*.swift|UNLOCK/LICENSE BY DLC'
    # Status strings written by the legacy app, matched during migration.
    'Sources/NPSDownloads/Migration/LegacyDownloadMigration.swift|download complete'
    'Sources/NPSDownloads/Migration/LegacyDownloadMigration.swift|extraction complete'
    'Sources/NPSDownloads/Migration/LegacyDownloadMigration.swift|missing zrif, license not created'
    # Default download folder name on disk.
    'Sources/NPSCore/Settings/*.swift|NPS Downloads'
    # UserDefaults key prefix written by NSToolbar.
    'Sources/NPSBrowserApp/Services/Preferences/ToolbarDisplayModeMigration.swift|NSToolbar Configuration '
    # Console brand name, never translated (LOCALIZATION.md), and the --ui-preview fixture.
    'Sources/NPSBrowserApp/Models/BrowserEntry+Catalogue.swift|PS Vita'
    'Sources/NPSBrowserApp/App/AppDelegate.swift|PS Vita'
    'Sources/NPSBrowserApp/App/AppDelegate.swift|Preview PS Vita Game'
)

UI_SINK='addButton\(withTitle:|messageText =|informativeText =|\.title =|toolTip =|setAccessibility[A-Za-z]*\(|placeholderString =|stringValue =|\.label =|paletteLabel =|labelWithString:|checkboxWithTitle:|NSButton\(title:|NSMenu\(title:|withTitle:|nameFieldStringValue =|\.prompt ='
PROSE='[A-Za-z]{2,} [A-Za-z]{2,}'
KEY_SHAPE='^[a-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+$'
LITERAL='"(\\.|[^"\\])*"'
RAW_STRING='#"([^"]|"[^#])*"#'

failures=0
for file in Sources/**/*.swift(N); do
    line_number=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + 1))
        [[ "$line" =~ '^[[:space:]]*//' ]] && continue
        [[ "$line" == *'"'* ]] || continue
        context=false
        for pattern in $IDENTIFIER_CONTEXTS; do
            if [[ "$line" =~ $pattern ]]; then context=true; break; fi
        done
        $context && continue
        sink=false
        [[ "$line" =~ $UI_SINK ]] && sink=true
        rest="$line"
        while [[ "$rest" =~ $RAW_STRING ]]; do rest="${rest/$MATCH/}"; done
        while [[ "$rest" =~ $LITERAL ]]; do
            literal="${MATCH[2,-2]}"
            rest="${rest[$((MEND + 1)),-1]}"
            text="$literal"
            while [[ "$text" =~ '\\\([^()]*(\([^()]*\))*[^()]*\)' ]]; do text="${text/$MATCH/ }"; done
            text="${text//\\[nrt]/ }"
            [[ "$text" =~ '[A-Za-z]' ]] || continue
            [[ "$text" =~ $KEY_SHAPE ]] && continue
            allowed=false
            for entry in $IDENTIFIER_LITERALS; do
                if [[ "$file" == ${~entry%%|*} && "$literal" == "${entry#*|}" ]]; then
                    allowed=true
                    break
                fi
            done
            $allowed && continue
            if [[ "$text" =~ $PROSE ]] || $sink; then
                print -r -u2 -- "$file:$line_number: hard-coded user-facing string \"$literal\""
                failures=$((failures + 1))
            fi
        done
    done < "$file"
done

if (( failures > 0 )); then
    print -u2 -- "$failures hard-coded string(s). Add a catalog key (see LOCALIZATION.md) or, for a runtime identifier, extend the allowlist in scripts/check-strings.sh."
    exit 1
fi
print "Strings OK: no hard-coded user-facing strings in Sources."
