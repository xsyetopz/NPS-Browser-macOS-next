import Foundation

enum CatalogueTextLoader {
  static func supports(_ url: URL) -> Bool { BrowserPreferences.isSupportedCatalogueURL(url) }

  static func fetchText(from url: URL) async throws -> String {
    guard supports(url) else { throw CatalogueRefreshError.invalidURL(url) }
    if url.isFileURL {
      let data = try Data(contentsOf: url, options: .mappedIfSafe)
      guard let text = String(data: data, encoding: .utf8) else {
        throw CatalogueRefreshError.invalidText(url)
      }
      return text
    }
    return try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<String, Error>) in
      URLSession.shared.dataTask(with: url) { data, response, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        guard let response = response as? HTTPURLResponse else {
          continuation.resume(throwing: CatalogueRefreshError.invalidResponse(url))
          return
        }
        guard (200..<300).contains(response.statusCode) else {
          continuation.resume(throwing: CatalogueRefreshError.httpStatus(url, response.statusCode))
          return
        }
        guard let data, let text = String(data: data, encoding: .utf8) else {
          continuation.resume(throwing: CatalogueRefreshError.invalidText(url))
          return
        }
        continuation.resume(returning: text)
      }.resume()
    }
  }
}
