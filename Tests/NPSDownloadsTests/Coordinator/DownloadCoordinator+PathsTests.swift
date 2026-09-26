import Foundation
import Testing
@testable import NPSDownloads

extension DownloadCoordinatorTests {
  @Test("sanitizes repeated PS3 PKG names without overwriting and snapshots each destination")
  func repeatedUnsafePS3TitlesUseSafeDistinctDestinations() async throws {
    let firstPackage = makePKGFixture(repetitions: 4)
    let secondPackage = makePKGFixture(repetitions: 5)
    let thirdPackage = makePKGFixture(repetitions: 6)
    let server = try FixtureHTTPServer { request in
      let body: Data
      switch request.path {
      case "/second": body = secondPackage
      case "/third": body = thirdPackage
      default: body = firstPackage
      }
      return FixtureHTTPResponse(body: body)
    }
    let initialDestination = try makeTemporaryDirectory()
    let changedDestination = try makeTemporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: initialDestination)
      try? FileManager.default.removeItem(at: changedDestination)
    }
    let preferences = LockedPreferences(
      DownloadPreferences(downloadDirectory: initialDestination, concurrentDownloads: 2)
    )
    let coordinator = try DownloadCoordinator(
      preferences: { preferences.snapshot() },
      persistenceURL: initialDestination.appendingPathComponent("jobs.plist"),
      urlSessionConfiguration: .ephemeral
    )
    let unsafeTitle = "../Unsafe: Name"
    func request(_ path: String) -> DownloadJobRequest {
      DownloadJobRequest(
        sourceURL: server.baseURL.appendingPathComponent(path),
        title: unsafeTitle,
        consoleType: "PS3",
        titleID: "NPUB12345"
      )
    }

    let first = try await coordinator.enqueue(request("first"))
    let second = try await coordinator.enqueue(request("second"))
    preferences.update(
      DownloadPreferences(downloadDirectory: changedDestination, concurrentDownloads: 2)
    )
    let third = try await coordinator.enqueue(request("third"))

    let firstDestination = try #require(first.destinationURL)
    let secondDestination = try #require(second.destinationURL)
    let thirdDestination = try #require(third.destinationURL)
    #expect(
      firstDestination.deletingLastPathComponent()
        == initialDestination.appendingPathComponent("PS3", isDirectory: true)
    )
    #expect(
      secondDestination.deletingLastPathComponent() == firstDestination.deletingLastPathComponent()
    )
    #expect(
      thirdDestination.deletingLastPathComponent()
        == changedDestination.appendingPathComponent("PS3", isDirectory: true)
    )
    #expect(firstDestination.lastPathComponent == "_Unsafe_ Name.pkg")
    #expect(secondDestination.lastPathComponent == "_Unsafe_ Name (2).pkg")
    #expect(thirdDestination.lastPathComponent == "_Unsafe_ Name.pkg")

    let results = try await withThrowingTaskGroup(
      of: DownloadSnapshot.self,
      returning: [DownloadSnapshot].self
    ) { group in
      for job in [first, second, third] {
        group.addTask { try await waitForTerminal(coordinator, id: job.id) }
      }
      var snapshots: [DownloadSnapshot] = []
      for try await snapshot in group { snapshots.append(snapshot) }
      return snapshots
    }
    let byID = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
    let firstResult = try #require(byID[first.id])
    let secondResult = try #require(byID[second.id])
    let thirdResult = try #require(byID[third.id])
    #expect(firstResult.state == .complete)
    #expect(secondResult.state == .complete)
    #expect(thirdResult.state == .complete)
    #expect(try Data(contentsOf: firstDestination) == firstPackage)
    #expect(try Data(contentsOf: secondDestination) == secondPackage)
    #expect(try Data(contentsOf: thirdDestination) == thirdPackage)
    #expect(
      !FileManager.default.fileExists(
        atPath: initialDestination.appendingPathComponent("Unsafe: Name.pkg").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: initialDestination.deletingLastPathComponent().appendingPathComponent(
          "Unsafe: Name.pkg"
        ).path
      )
    )
  }
}

extension DownloadCoordinatorTests {
  @Test("names files from the language-independent file title, not the localized title")
  func fileTitleNamesDestinationsInEveryLanguage() async throws {
    // Arrange
    let destination = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: destination) }
    let coordinator = try makeCoordinator(
      destination: destination,
      persistence: destination.appendingPathComponent("jobs.plist")
    )
    let source = try #require(URL(string: "http://127.0.0.1:9/update.pkg"))
    func request(title: String) -> DownloadJobRequest {
      DownloadJobRequest(
        sourceURL: source,
        title: title,
        consoleType: "PSV",
        titleID: "PCSA00007",
        fileTitle: "Example Update"
      )
    }

    // Act
    let chinese = try await coordinator.enqueue(request(title: "Example 更新"))
    let english = try await coordinator.enqueue(request(title: "Example Update (English)"))

    // Assert
    #expect(chinese.request.title == "Example 更新")
    #expect(chinese.destinationURL?.lastPathComponent == "Example Update.pkg")
    #expect(english.destinationURL?.lastPathComponent == "Example Update (2).pkg")
  }
}
