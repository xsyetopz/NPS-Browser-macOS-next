import Foundation

struct PreferencesFormValues: Equatable, Sendable {
  var downloadDirectoryPath: String
  var hideInvalidURLItems: Bool
  var concurrentDownloads: Int
  var extractAfterDownload: Bool
  var keepPackage: Bool
  var saveAsZip: Bool
  var createLicense: Bool
  var compressPSPISO: Bool
  var compressionFactor: Int
}
