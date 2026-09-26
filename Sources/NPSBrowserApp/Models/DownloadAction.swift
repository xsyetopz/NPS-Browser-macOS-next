import Foundation

enum DownloadAction: Int, Equatable, Sendable {
  case pause = 1
  case resume
  case restart
  case retryExtraction
  case remove
  case reveal
}
