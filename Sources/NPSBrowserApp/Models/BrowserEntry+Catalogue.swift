import Foundation
import NPSBrowserAppResources
import NPSCore

extension BrowserEntry {
  init(item: CatalogItem) {
    let console: String
    switch item.consoleType {
    case .PSV: console = "PS Vita"
    case .PS3: console = "PS3"
    case .PSP: console = "PSP"
    case .PSM: console = AppResources.localized("section.psm")
    case .PSX: console = "PSX"
    }
    let displayTitle: String
    if !item.name.isEmpty {
      displayTitle = item.name
    } else if let originalName = item.originalName, !originalName.isEmpty {
      displayTitle = originalName
    } else {
      displayTitle = AppResources.localized("catalog.untitled")
    }
    self.init(
      id: item.id,
      title: displayTitle,
      titleID: item.titleID.isEmpty ? "—" : item.titleID,
      console: console,
      consoleCode: item.consoleType.rawValue,
      category: item.fileType.rawValue,
      region: item.region ?? "",
      fileSize: item.fileSize,
      packageURL: item.packageURL,
      rapDownloadURL: item.rapDownloadURL,
      sha256: item.sha256,
      contentID: item.contentID
    )
  }

  init(
    compatibilityPack: CompatibilityPack,
    matchingPatchURL: URL?,
    matchingPackURL: URL? = nil,
    matchingPackTitle: String? = nil
  ) {
    self.init(
      id: compatibilityPack.id,
      title: compatibilityPack.displayName ?? compatibilityPack.titleID,
      titleID: compatibilityPack.titleID,
      console: "PS Vita",
      consoleCode: ConsoleType.PSV.rawValue,
      category: compatibilityPack.kind.fileType.rawValue,
      region: "",
      fileSize: nil,
      packageURL: compatibilityPack.downloadURL,
      sha256: nil,
      contentID: nil,
      isCompatibilityPack: true,
      compatibilityPackKind: compatibilityPack.kind,
      compatibilityPatchURL: matchingPatchURL,
      matchingPackURL: matchingPackURL,
      matchingPackTitle: matchingPackTitle
    )
  }
}
