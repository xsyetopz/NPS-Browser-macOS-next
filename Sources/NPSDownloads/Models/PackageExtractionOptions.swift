import Foundation

public struct PackageExtractionOptions: Codable, Hashable, Sendable {
  public let keepPackage: Bool
  public let saveAsZip: Bool
  public let createLicense: Bool
  public let compressPSPISO: Bool
  public let compressionFactor: Int

  public init(
    keepPackage: Bool = true,
    saveAsZip: Bool = false,
    createLicense: Bool = true,
    compressPSPISO: Bool = false,
    compressionFactor: Int = 1
  ) {
    self.keepPackage = keepPackage
    self.saveAsZip = saveAsZip
    self.createLicense = createLicense
    self.compressPSPISO = compressPSPISO
    self.compressionFactor = min(9, max(0, compressionFactor))
  }
}
