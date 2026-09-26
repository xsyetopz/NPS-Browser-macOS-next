import Foundation
import Testing
@testable import NPSDownloads

extension CompatibilityPackTests {
  @Test("persisted download requests decode when the newer patch mode key is absent")
  func oldDownloadRequestDecodesWithoutPatchMode() throws {
    let request = DownloadJobRequest(
      sourceURL: URL(string: "https://downloads.example/patch.ppk")!,
      title: "Example Patch",
      consoleType: "PSV",
      titleID: "PCSE00640",
      fileExtension: "ppk",
      extractAfterDownload: true,
      compatibilityPatchMode: .overlayExistingOutput
    )
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let encoded = try encoder.encode(request)
    var archivedFields = try #require(
      PropertyListSerialization.propertyList(
        from: encoded,
        options: [.mutableContainers],
        format: nil
      ) as? [String: Any]
    )
    #expect(archivedFields["compatibilityPatchMode"] != nil)
    archivedFields.removeValue(forKey: "compatibilityPatchMode")
    let oldArchive = try PropertyListSerialization.data(
      fromPropertyList: archivedFields,
      format: .binary,
      options: 0
    )

    let restored = try PropertyListDecoder().decode(DownloadJobRequest.self, from: oldArchive)

    #expect(restored.compatibilityPatchMode == nil)
    #expect(restored.sourceURL == request.sourceURL)
    #expect(restored.extractAfterDownload)
  }
}
