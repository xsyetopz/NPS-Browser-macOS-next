set shell := ["/bin/zsh", "-cu"]
set dotenv-load := false

# Compile the Swift package in debug configuration.
build:
    scripts/swiftpm.sh build

# Run package tests with Swift Testing.
test:
    scripts/swiftpm.sh test

# Check formatting (.swift-format) and lint rules (.swiftlint.yml).
lint:
    scripts/lint.sh

# Rewrite sources with swift-format. SwiftLint autocorrect is not used: its
# trailing-closure fix produces code that does not compile (e.g. `}?? x`).
format:
    scripts/lint.sh --fix

# Assemble a universal macOS application bundle.
app:
    scripts/assemble-app.sh

# Lint, test, assemble and verify the bundle. The deployment target defaults to
# macOS 10.15, raised only when the selected SDK cannot target it; CI pins 10.15.
verify:
    scripts/lint.sh
    scripts/swiftpm.sh test
    scripts/assemble-app.sh
    scripts/verify-app-bundle.sh
