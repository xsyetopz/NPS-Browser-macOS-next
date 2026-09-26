#!/bin/zsh
# Enforces the layout rules:
# - Swift source files have at most 350 lines, test files at most 1000.
# - Tests/<Target>Tests mirrors Sources/<Target>: every test file outside
#   Support/ and Fixtures/ is named <Stem>Tests.swift or <Stem>Tests+<Part>.swift
#   and tests Sources/<Target>/<same relative dir>/<Stem>.swift.
# - Every top-level test suite type and free `@Test` pins the UI language with
#   the `.sourceEnglish` trait, so text assertions hold on any Mac language.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE_LIMIT=350
TEST_LIMIT=1000
failures=0

fail() {
    print -u2 -- "$1"
    failures=$((failures + 1))
}

for file in Sources/**/*.swift(N); do
    lines=$(wc -l < "$file" | tr -d ' ')
    (( lines <= SOURCE_LIMIT )) || fail "$file: $lines lines (limit $SOURCE_LIMIT)"
done

for file in Tests/**/*.swift(N); do
    lines=$(wc -l < "$file" | tr -d ' ')
    (( lines <= TEST_LIMIT )) || fail "$file: $lines lines (limit $TEST_LIMIT)"

    relative="${file#Tests/}"
    target_dir="${relative%%/*}"
    inner="${relative#*/}"
    [[ "$inner" == Support/* || "$inner" == Fixtures/* ]] && continue

    target="${target_dir%Tests}"
    name="${inner:t:r}"
    subdir="${inner:h}"
    [[ "$subdir" == "$inner" || "$subdir" == "." ]] && subdir=""
    if [[ ! "$name" =~ '^(.+)Tests(\+[A-Za-z0-9]+)?$' ]]; then
        fail "$file: test files outside Support/ must be named <Stem>Tests[+Part].swift"
        continue
    fi
    stem="${match[1]}"
    source="Sources/$target/${subdir:+$subdir/}$stem.swift"
    [[ -f "$source" ]] || fail "$file: no matching source $source"

    previous=""
    line_number=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + 1))
        if [[ "$line" == @Test* && "$line" != *.sourceEnglish* ]]; then
            fail "$file:$line_number: free @Test must include the .sourceEnglish trait"
        fi
        if [[ "$line" =~ '^(final )?(struct|class|enum) [A-Za-z0-9_]+Tests([^A-Za-z0-9_]|$)' ]]; then
            [[ "$previous" == *.sourceEnglish* ]] ||
                fail "$file:$line_number: test suite must be declared with @Suite(.sourceEnglish)"
        fi
        [[ "$line" == @MainActor* ]] || previous="$line"
    done < "$file"
done

if (( failures > 0 )); then
    print -u2 -- "$failures structure violation(s)."
    exit 1
fi
print "Structure OK: sources <= $SOURCE_LIMIT lines, tests <= $TEST_LIMIT lines, tests mirror sources."
