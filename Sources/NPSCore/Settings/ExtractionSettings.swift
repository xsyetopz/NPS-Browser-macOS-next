import Foundation

public struct ExtractionSettings: Equatable, Sendable {
  public var extractAfterDownload: Bool
  public var keepPackage: Bool
  public var saveAsZip: Bool
  public var createLicense: Bool
  public var compressPSPISO: Bool
  public var compressionFactor: Int
  public var unpackPS3Packages: Bool

  public init(
    extractAfterDownload: Bool = true,
    keepPackage: Bool = false,
    saveAsZip: Bool = false,
    createLicense: Bool = true,
    compressPSPISO: Bool = false,
    compressionFactor: Int = 1,
    unpackPS3Packages: Bool = false
  ) {
    self.extractAfterDownload = extractAfterDownload
    self.keepPackage = keepPackage
    self.saveAsZip = saveAsZip
    self.createLicense = createLicense
    self.compressPSPISO = compressPSPISO
    self.compressionFactor = max(0, compressionFactor)
    self.unpackPS3Packages = unpackPS3Packages
  }
}
