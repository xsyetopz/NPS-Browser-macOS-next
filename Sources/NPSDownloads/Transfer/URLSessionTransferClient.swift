import Foundation
import NPSCore

private final class TransferContext: @unchecked Sendable {
  let id: UUID
  let task: URLSessionDownloadTask
  let continuation: CheckedContinuation<TransferCompletion, Error>
  let onProgress: @Sendable (Int64, Int64) -> Void
  var completion: TransferCompletion?
  var completionError: LocalizedMessage?
  var resumeData: Data?
  var resumeDataCallbackPending = false
  var transferError: TransferFailure?
  var didComplete = false

  init(
    id: UUID,
    task: URLSessionDownloadTask,
    continuation: CheckedContinuation<TransferCompletion, Error>,
    onProgress: @escaping @Sendable (Int64, Int64) -> Void
  ) {
    self.id = id
    self.task = task
    self.continuation = continuation
    self.onProgress = onProgress
  }
}

/// A narrow URLSession delegate adapter. URLSessionDownloadTask is available on
/// macOS 10.10; unlike URLSession's newer async APIs, this stays compatible with
/// the package's 10.15 deployment target.
final class URLSessionTransferClient: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private let fileManager = FileManager.default
  private var contexts: [Int: TransferContext] = [:]
  private var taskIDs: [UUID: Int] = [:]
  private var session: URLSession!

  init(configuration: URLSessionConfiguration = .default) {
    let delegateQueue = OperationQueue()
    delegateQueue.name = "com.npsbrowser.download-delegate"
    delegateQueue.maxConcurrentOperationCount = 1
    delegateQueue.qualityOfService = .utility
    super.init()
    // URLSession's delegate is immutable after creation, so initialize it
    // after NSObject initialization has completed.
    session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
  }

  func download(
    id: UUID,
    sourceURL: URL,
    resumeData: Data?,
    onProgress: @escaping @Sendable (Int64, Int64) -> Void
  ) async throws -> TransferCompletion {
    try await withCheckedThrowingContinuation { continuation in
      let task: URLSessionDownloadTask
      if let resumeData {
        task = session.downloadTask(withResumeData: resumeData)
      } else {
        task = session.downloadTask(with: sourceURL)
      }

      let context = TransferContext(
        id: id,
        task: task,
        continuation: continuation,
        onProgress: onProgress
      )
      lock.lock()
      contexts[task.taskIdentifier] = context
      taskIDs[id] = task.taskIdentifier
      lock.unlock()
      task.resume()
    }
  }

  func pause(id: UUID) {
    lock.lock()
    let taskIdentifier = taskIDs[id]
    let context = taskIdentifier.flatMap { contexts[$0] }
    context?.resumeDataCallbackPending = true
    lock.unlock()
    guard let context else { return }
    context.task.cancel { [weak self] data in
      guard let self else { return }
      self.lock.lock()
      context.resumeData = data
      if let transferError = context.transferError {
        context.transferError = TransferFailure(
          message: transferError.message,
          resumeData: data ?? transferError.resumeData
        )
      }
      context.resumeDataCallbackPending = false
      let completed = self.takeCompletedContext(context.task.taskIdentifier)
      self.lock.unlock()
      if let completed { self.finish(completed) }
    }
  }

  func cancel(id: UUID) {
    lock.lock()
    let taskIdentifier = taskIDs[id]
    let task = taskIdentifier.flatMap { contexts[$0]?.task }
    lock.unlock()
    task?.cancel()
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    lock.lock()
    let progress = contexts[downloadTask.taskIdentifier]?.onProgress
    lock.unlock()
    progress?(totalBytesWritten, totalBytesExpectedToWrite)
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    lock.lock()
    let context = contexts[downloadTask.taskIdentifier]
    lock.unlock()
    guard let context else { return }

    do {
      let response = downloadTask.response as? HTTPURLResponse
      let transferDirectory = fileManager.temporaryDirectory.appendingPathComponent(
        "NPSBrowserTransfers",
        isDirectory: true
      )
      try fileManager.createDirectory(at: transferDirectory, withIntermediateDirectories: true)
      let stagedURL = transferDirectory.appendingPathComponent("\(context.id.uuidString).download")
      if fileManager.fileExists(atPath: stagedURL.path) {
        try fileManager.removeItem(at: stagedURL)
      }
      try fileManager.copyItem(at: location, to: stagedURL)
      let completion = TransferCompletion(
        temporaryURL: stagedURL,
        response: TransferResponse(
          statusCode: response?.statusCode ?? 0,
          mimeType: response?.mimeType,
          expectedContentLength: response?.expectedContentLength ?? -1
        )
      )
      lock.lock()
      contexts[downloadTask.taskIdentifier]?.completion = completion
      lock.unlock()
    } catch {
      lock.lock()
      contexts[downloadTask.taskIdentifier]?.completionError = LocalizedMessage(error)
      lock.unlock()
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    lock.lock()
    if let context = contexts[task.taskIdentifier] {
      context.didComplete = true
      if let error {
        let nsError = error as NSError
        let resumeData =
          (nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data) ?? context.resumeData
        context.transferError = TransferFailure(
          message: LocalizedMessage(error),
          resumeData: resumeData
        )
      } else if let completionError = context.completionError {
        context.transferError = TransferFailure(
          message: completionError,
          resumeData: context.resumeData
        )
      } else if context.completion == nil {
        context.transferError = TransferFailure(
          message: LocalizedMessage("error.download.transferEndedWithoutFile"),
          resumeData: context.resumeData
        )
      }
    }
    let completed = takeCompletedContext(task.taskIdentifier)
    lock.unlock()
    if let completed { finish(completed) }
  }

  private func takeCompletedContext(
    _ taskIdentifier: Int
  ) -> (TransferContext, Result<TransferCompletion, TransferFailure>)? {
    guard let context = contexts[taskIdentifier], context.didComplete,
      !context.resumeDataCallbackPending
    else { return nil }
    contexts.removeValue(forKey: taskIdentifier)
    taskIDs.removeValue(forKey: context.id)
    if let transferError = context.transferError { return (context, .failure(transferError)) }
    guard let completion = context.completion else { return nil }
    return (context, .success(completion))
  }

  private func finish(_ completed: (TransferContext, Result<TransferCompletion, TransferFailure>)) {
    if case .failure = completed.1, let temporaryURL = completed.0.completion?.temporaryURL {
      try? fileManager.removeItem(at: temporaryURL)
    }
    completed.0.continuation.resume(with: completed.1)
  }
}
