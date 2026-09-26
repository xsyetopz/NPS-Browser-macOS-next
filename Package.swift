// swift-tools-version: 6.1
import PackageDescription

// Realm 20.0.5 fixes Xcode 27 compilation, while 20.0.3 is the newest release
// that supports Xcode 16.4 / Swift 6.1. Select by the compiler evaluating this
// manifest so Swift 6 callers keep the matching Realm toolchain support.
#if compiler(>=6.3)
  let realmSwiftDependency: Package.Dependency = .package(
    url: "https://github.com/realm/realm-swift.git",
    exact: "20.0.5"
  )
#else
  let realmSwiftDependency: Package.Dependency = .package(
    url: "https://github.com/realm/realm-swift.git",
    exact: "20.0.3"
  )
#endif

let package = Package(
  name: "NPSBrowser",
  defaultLocalization: "en-US",
  platforms: [.macOS(.v10_15)],
  products: [
    .library(name: "NPSCore", targets: ["NPSCore"]),
    .library(name: "NPSPersistence", targets: ["NPSPersistence"]),
    .library(name: "NPSDownloads", targets: ["NPSDownloads"]),
    .executable(name: "NPSBrowserApp", targets: ["NPSBrowserApp"]),
    .executable(name: "Cpkg2zip", targets: ["Cpkg2zip"]),
  ],
  dependencies: [realmSwiftDependency],
  targets: [
    .target(name: "NPSCore", path: "Sources/NPSCore", resources: [.process("Resources")]),
    .target(
      name: "NPSPersistence",
      dependencies: ["NPSCore", .product(name: "RealmSwift", package: "realm-swift")],
      path: "Sources/NPSPersistence"
    ), .target(name: "NPSDownloads", dependencies: ["NPSCore"], path: "Sources/NPSDownloads"),
    .executableTarget(
      name: "Cpkg2zip",
      path: "Sources/CPkg2Zip",
      cSettings: [.define("NPS_PKG2ZIP_PORTABLE_ONLY")]
    ),
    .target(
      name: "NPSBrowserAppResources",
      dependencies: ["NPSCore"],
      path: "Sources/NPSBrowserAppResources",
      exclude: ["IconBuild"],
      resources: [.process("Resources")]
    ),
    .executableTarget(
      name: "NPSBrowserApp",
      dependencies: ["NPSCore", "NPSPersistence", "NPSDownloads", "NPSBrowserAppResources"],
      path: "Sources/NPSBrowserApp"
    ), .testTarget(name: "NPSCoreTests", dependencies: ["NPSCore"], path: "Tests/NPSCoreTests"),
    .testTarget(
      name: "NPSPersistenceTests",
      dependencies: [
        "NPSPersistence", "NPSCore", .product(name: "RealmSwift", package: "realm-swift"),
      ],
      path: "Tests/NPSPersistenceTests",
      resources: [.process("Fixtures")]
    ),
    .testTarget(
      name: "NPSDownloadsTests",
      dependencies: ["NPSDownloads", "NPSCore"],
      path: "Tests/NPSDownloadsTests"
    ),
    .testTarget(
      name: "NPSBrowserAppTests",
      dependencies: ["NPSBrowserApp", "NPSCore", "NPSPersistence", "NPSDownloads"],
      path: "Tests/NPSBrowserAppTests",
      resources: [.process("Fixtures")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
