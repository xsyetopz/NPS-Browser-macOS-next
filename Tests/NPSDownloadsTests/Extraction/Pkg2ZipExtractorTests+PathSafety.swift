import Foundation
import Testing

@Suite(.sourceEnglish)
struct Pkg2ZipPathSafetyTests {
  @Test("pkg2zip output APIs reject traversal, absolute paths and symlink escapes")
  func unsafePathsAreRejectedByCOutputLayer() throws {
    let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let sourceDirectory = packageRoot.appendingPathComponent("Sources/CPkg2Zip", isDirectory: true)
    let systemSource = sourceDirectory.appendingPathComponent("pkg2zip_sys.c")
    let header = sourceDirectory.appendingPathComponent("pkg2zip_sys.h")
    guard FileManager.default.fileExists(atPath: systemSource.path),
      FileManager.default.fileExists(atPath: header.path)
    else {
      Issue.record("The pkg2zip C sources are missing from the repository checkout.")
      return
    }

    let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NPSPkg2ZipPathTest-\(UUID().uuidString)",
      isDirectory: true
    )
    let work = workspace.appendingPathComponent("work", isDirectory: true)
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workspace) }

    let sentinel = workspace.appendingPathComponent("sentinel")
    try Data("keep".utf8).write(to: sentinel)
    try FileManager.default.createSymbolicLink(
      at: work.appendingPathComponent("escape"),
      withDestinationURL: workspace
    )

    let harness = workspace.appendingPathComponent("path-probe.c")
    try """
    #include "pkg2zip_sys.h"
    #include <string.h>
    int main(int argc, char** argv) {
        if (argc != 3) return 64;
        if (strcmp(argv[1], "mkdir") == 0) { sys_mkdir(argv[2]); return 0; }
        if (strcmp(argv[1], "create") == 0) { sys_file f = sys_create(argv[2]); \
    sys_close(f); return 0; }
        return 64;
    }
    """.write(to: harness, atomically: true, encoding: .utf8)

    let executable = workspace.appendingPathComponent("path-probe")
    let compile = try runProcess(
      executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
      arguments: [
        "clang", "-std=c99", "-D_GNU_SOURCE", "-I", sourceDirectory.path, harness.path,
        systemSource.path, "-o", executable.path,
      ],
      currentDirectory: workspace
    )
    try #require(compile.status == 0, "C safety probe did not compile: \(compile.output)")

    let safe = try runProcess(
      executable: executable,
      arguments: ["mkdir", "nested"],
      currentDirectory: work
    )
    #expect(safe.status == 0)
    let safeFile = try runProcess(
      executable: executable,
      arguments: ["create", "nested/safe.bin"],
      currentDirectory: work
    )
    #expect(safeFile.status == 0)
    #expect(
      FileManager.default.fileExists(atPath: work.appendingPathComponent("nested/safe.bin").path)
    )

    let traversal = try runProcess(
      executable: executable,
      arguments: ["create", "../escaped"],
      currentDirectory: work
    )
    let absolute = try runProcess(
      executable: executable,
      arguments: ["create", sentinel.path],
      currentDirectory: work
    )
    let symlink = try runProcess(
      executable: executable,
      arguments: ["create", "escape/sentinel"],
      currentDirectory: work
    )
    #expect(traversal.status != 0)
    #expect(absolute.status != 0)
    #expect(symlink.status != 0)
    #expect(String(bytes: try Data(contentsOf: sentinel), encoding: .utf8) == "keep")
    #expect(
      !FileManager.default.fileExists(atPath: workspace.appendingPathComponent("escaped").path)
    )
  }

  @Test("PSP item name length is rejected before reading into the fixed filename buffer")
  func oversizedPSPItemNameIsRejected() throws {
    let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let sourceDirectory = packageRoot.appendingPathComponent("Sources/CPkg2Zip", isDirectory: true)
    let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NPSPkg2ZipNameBoundsTest-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workspace) }

    let harness = workspace.appendingPathComponent("name-bounds-probe.c")
    try """
    #define main pkg2zip_command_main
    #include "pkg2zip.c"
    #undef main
    #include <fcntl.h>
    #include <stdint.h>
    #include <unistd.h>

    int main(void) {
        uint8_t raw_key[16] = {0};
        uint8_t iv[16] = {0};
        aes128_key key;
        aes128_init(&key, raw_key);
        uint8_t item[32] = {0};
        uint32_t name_offset = 64;
        uint32_t name_size = ZIP_MAX_FILENAME;
        item[0] = (uint8_t)(name_offset >> 24); item[1] = (uint8_t)(name_offset >> 16);
        item[2] = (uint8_t)(name_offset >> 8); item[3] = (uint8_t)name_offset;
        item[4] = (uint8_t)(name_size >> 24); item[5] = (uint8_t)(name_size >> 16);
        item[6] = (uint8_t)(name_size >> 8); item[7] = (uint8_t)name_size;
        item[24] = 0x90;
        aes128_ctr_xor(&key, iv, 0, item, sizeof(item));
        int fd = open("pkg-name-bounds.fixture", O_RDWR | O_CREAT | O_TRUNC, 0600);
        if (fd < 0 || ftruncate(fd, 8192) != 0 || \
    pwrite(fd, item, sizeof(item), 0) != sizeof(item)) return 2;
        char category[64] = {0}, title[256] = {0};
        find_psp_sfo(&key, &key, iv, (sys_file)(intptr_t)fd, 8192, 0, 0, 1, category, title);
        close(fd);
        return 0;
    }
    """.write(to: harness, atomically: true, encoding: .utf8)

    let cFiles = try FileManager.default.contentsOfDirectory(
      at: sourceDirectory,
      includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "c" && $0.lastPathComponent != "pkg2zip.c" }.sorted {
      $0.lastPathComponent < $1.lastPathComponent
    }
    func compileProbe(named name: String, sanitizerFlags: [String]) throws -> URL {
      let executable = workspace.appendingPathComponent(name)
      let compile = try runProcess(
        executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
        arguments: ["clang", "-std=c99", "-D_GNU_SOURCE", "-DNPS_PKG2ZIP_PORTABLE_ONLY"]
          + sanitizerFlags + ["-O1", "-g", "-I", sourceDirectory.path, harness.path]
          + cFiles.map(\.path) + ["-o", executable.path],
        currentDirectory: workspace
      )
      try #require(compile.status == 0, "PSP item bounds probe did not compile: \(compile.output)")
      return executable
    }

    let result: (status: Int32, output: String)
    do {
      let probe = try compileProbe(
        named: "name-bounds-probe",
        sanitizerFlags: ["-fsanitize=address"]
      )
      result = try runProcess(
        executable: probe,
        arguments: [],
        currentDirectory: workspace,
        timeout: 30
      )
    } catch is ProcessTimedOut {
      // Some sanitizer runtimes deadlock while initializing on a newer macOS
      // (Xcode 16.3's ASan on macOS 27 spins in AsanInitInternal before main).
      // Rerun the bounds check uninstrumented; a real hang in pkg2zip times out
      // again and fails the test.
      let probe = try compileProbe(named: "name-bounds-probe-plain", sanitizerFlags: [])
      result = try runProcess(
        executable: probe,
        arguments: [],
        currentDirectory: workspace,
        timeout: 30
      )
    }
    #expect(result.status != 0)
    #expect(result.output.contains("very long name"))
    #expect(!result.output.contains("AddressSanitizer"))
  }
}

private struct ProcessTimedOut: Error {}

/// Output goes to a file rather than a pipe so a chatty child cannot block on a
/// full pipe buffer, and a child that never exits is killed after `timeout`.
private func runProcess(
  executable: URL,
  arguments: [String],
  currentDirectory: URL,
  timeout: TimeInterval = 120
) throws -> (status: Int32, output: String) {
  let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
    "nps-process-\(UUID().uuidString).log"
  )
  FileManager.default.createFile(atPath: outputURL.path, contents: nil)
  let outputHandle = try FileHandle(forWritingTo: outputURL)
  defer {
    try? outputHandle.close()
    try? FileManager.default.removeItem(at: outputURL)
  }
  let process = Process()
  process.executableURL = executable
  process.arguments = arguments
  process.currentDirectoryURL = currentDirectory
  process.standardOutput = outputHandle
  process.standardError = outputHandle
  let exited = DispatchSemaphore(value: 0)
  process.terminationHandler = { _ in exited.signal() }
  try process.run()
  if exited.wait(timeout: .now() + timeout) == .timedOut {
    kill(process.processIdentifier, SIGKILL)
    _ = exited.wait(timeout: .now() + 5)
    throw ProcessTimedOut()
  }
  let output = try Data(contentsOf: outputURL)
  return (process.terminationStatus, String(bytes: output, encoding: .utf8) ?? "")
}
