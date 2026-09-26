import Foundation

/// Synchronous access to the legacy UserDefaults keys. UserDefaults is thread-safe;
/// snapshots contain only Sendable value types and can be sent to other actors.
public final class SettingsStore: @unchecked Sendable {
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  public func snapshot() -> AppSettings {
    var catalogueURLs: [CatalogSource: URL] = [:]
    for source in CatalogSource.allCases {
      let persisted = urlValue(forKey: source.rawValue)
      catalogueURLs[source] = persisted.flatMap(Self.validatedCatalogueURL) ?? source.defaultURL
    }

    let downloadsKey = "dl_library_location"
    let storedDirectory = urlValue(forKey: downloadsKey)
    let validatedDownloadDirectory = storedDirectory.flatMap(Self.validatedFileURL)
    let downloadDirectory = validatedDownloadDirectory ?? Self.defaultDownloadDirectory
    let hasExplicitLibraryDirectory = defaults.object(forKey: "dl_library_folder") != nil
    let storedLibraryDirectory = urlValue(forKey: "dl_library_folder")
    let downloadLibraryDirectory: URL
    if hasExplicitLibraryDirectory {
      downloadLibraryDirectory =
        storedLibraryDirectory.flatMap(Self.validatedFileURL) ?? Self.defaultLibraryDirectory
    } else {
      // Older releases used dl_library_location for both downloaded files and
      // extracted/library output. Preserve that destination until the user
      // explicitly saves the newer dl_library_folder setting.
      downloadLibraryDirectory = validatedDownloadDirectory ?? Self.defaultLibraryDirectory
    }

    let savedConcurrency = defaults.object(forKey: "dl_concurrent_downloads") as? Int ?? 3
    let concurrency = savedConcurrency > 0 ? savedConcurrency : 3

    let savedCompression = defaults.object(forKey: "xt_compression_factor") as? Int ?? 1
    let extraction = ExtractionSettings(
      extractAfterDownload: bool("xt_extract_after_downloading", default: true),
      keepPackage: bool("xt_keep_pkg", default: false),
      saveAsZip: bool("xt_save_as_zip", default: false),
      createLicense: bool("xt_create_license", default: true),
      compressPSPISO: bool("xt_compress_psp_iso", default: false),
      compressionFactor: savedCompression,
      unpackPS3Packages: bool("xt_unpack_ps3_packages", default: false)
    )

    return AppSettings(
      catalogueURLs: catalogueURLs,
      downloadDirectory: downloadDirectory,
      downloadLibraryDirectory: downloadLibraryDirectory,
      concurrentDownloads: concurrency,
      extraction: extraction,
      hideInvalidURLItems: bool("dsp_hide_invalid_url_items", default: true)
    )
  }

  public func catalogueURL(for source: CatalogSource) -> URL {
    urlValue(forKey: source.rawValue).flatMap(Self.validatedCatalogueURL) ?? source.defaultURL
  }

  public func setCatalogueURL(_ url: URL, for source: CatalogSource) throws {
    guard let validated = Self.validatedCatalogueURL(url) else {
      throw SettingsError.invalidCatalogueURL(source, url.absoluteString)
    }
    defaults.set(validated, forKey: source.rawValue)
  }

  public func setDownloadDirectory(_ url: URL) throws {
    guard let validated = Self.validatedFileURL(url) else {
      throw SettingsError.invalidDownloadDirectory(url)
    }
    defaults.set(validated, forKey: "dl_library_location")
  }

  public func setDownloadLibraryDirectory(_ url: URL) throws {
    guard let validated = Self.validatedFileURL(url) else {
      throw SettingsError.invalidDownloadDirectory(url)
    }
    defaults.set(validated, forKey: "dl_library_folder")
  }

  public func setConcurrentDownloads(_ count: Int) throws {
    guard count > 0 else { throw SettingsError.invalidConcurrency(count) }
    defaults.set(count, forKey: "dl_concurrent_downloads")
  }

  public func updateExtractionSettings(_ settings: ExtractionSettings) {
    defaults.set(settings.extractAfterDownload, forKey: "xt_extract_after_downloading")
    defaults.set(settings.keepPackage, forKey: "xt_keep_pkg")
    defaults.set(settings.saveAsZip, forKey: "xt_save_as_zip")
    defaults.set(settings.createLicense, forKey: "xt_create_license")
    defaults.set(settings.compressPSPISO, forKey: "xt_compress_psp_iso")
    defaults.set(settings.compressionFactor, forKey: "xt_compression_factor")
    defaults.set(settings.unpackPS3Packages, forKey: "xt_unpack_ps3_packages")
  }

  public func setHidesInvalidURLItems(_ hide: Bool) {
    defaults.set(hide, forKey: "dsp_hide_invalid_url_items")
  }

  private func bool(_ key: String, default fallback: Bool) -> Bool {
    guard defaults.object(forKey: key) != nil else { return fallback }
    return defaults.bool(forKey: key)
  }

  private func urlValue(forKey key: String) -> URL? {
    // Legacy catalogue URI strings must be parsed directly: UserDefaults.url
    // treats a literal `file://` string as a relative file path. URL values
    // stored by newer code are exposed by UserDefaults as absolute path strings,
    // so retain its URL decoding for strings without a scheme.
    if let string = defaults.string(forKey: key), let parsed = URL(string: string),
      parsed.scheme != nil
    {
      return parsed
    }
    return defaults.url(forKey: key)
  }

  private static let defaultDownloadDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Downloads", isDirectory: true)
  private static let defaultLibraryDirectory = defaultDownloadDirectory.appendingPathComponent(
    "NPS Downloads",
    isDirectory: true
  )

  private static func validatedCatalogueURL(_ url: URL) -> URL? {
    guard url.absoluteURL == url else { return nil }
    if url.isFileURL {
      guard url.path.hasPrefix("/"), url.user == nil, url.password == nil else { return nil }
      return url
    }
    guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = url.host, !host.isEmpty, url.user == nil, url.password == nil
    else { return nil }
    // The archived app defaulted to cleartext URLs. NPS serves the same catalogue
    // paths over TLS, so upgrade those saved defaults to satisfy macOS ATS.
    if scheme == "http", host.caseInsensitiveCompare("nopaystation.com") == .orderedSame {
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
      components?.scheme = "https"
      return components?.url
    }
    return url
  }

  private static func validatedFileURL(_ url: URL) -> URL? {
    guard url.isFileURL, url.path.hasPrefix("/") else { return nil }
    return URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: true)
  }
}
