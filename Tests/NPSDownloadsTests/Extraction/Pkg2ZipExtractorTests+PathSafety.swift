import Foundation
import Testing
@testable import NPSDownloads

@Suite(.sourceEnglish)
struct Pkg2ZipPathSafetyTests {
  @Test("pkg2zip output APIs reject traversal, absolute paths and symlink escapes")
  func unsafePathsAreRejectedByCOutputLayer() async throws {
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
    let compile = try await runProcess(
      executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
      arguments: [
        "clang", "-std=c99", "-D_GNU_SOURCE", "-I", sourceDirectory.path, harness.path,
        systemSource.path, "-o", executable.path,
      ],
      currentDirectory: workspace
    )
    try #require(compile.status == 0, "C safety probe did not compile: \(compile.output)")

    let safe = try await runProcess(
      executable: executable,
      arguments: ["mkdir", "nested"],
      currentDirectory: work
    )
    #expect(safe.status == 0)
    let safeFile = try await runProcess(
      executable: executable,
      arguments: ["create", "nested/safe.bin"],
      currentDirectory: work
    )
    #expect(safeFile.status == 0)
    #expect(
      FileManager.default.fileExists(atPath: work.appendingPathComponent("nested/safe.bin").path)
    )

    let traversal = try await runProcess(
      executable: executable,
      arguments: ["create", "../escaped"],
      currentDirectory: work
    )
    let absolute = try await runProcess(
      executable: executable,
      arguments: ["create", sentinel.path],
      currentDirectory: work
    )
    let symlink = try await runProcess(
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
  func oversizedPSPItemNameIsRejected() async throws {
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
        char category[SFO_STRING_SIZE] = {0}, title[SFO_STRING_SIZE] = {0};
        find_psp_sfo(&key, &key, iv, (sys_file)(intptr_t)fd, 8192, 0, 0, 1, category, title);
        close(fd);
        return 0;
    }
    """.write(to: harness, atomically: true, encoding: .utf8)

    let result = try await runPkg2ZipProbe(
      harness: harness,
      named: "name-bounds-probe",
      workspace: workspace
    )
    #expect(result.status != 0)
    #expect(result.output.contains("very long name"))
    #expect(!result.output.contains("AddressSanitizer"))
  }
}

extension Pkg2ZipPathSafetyTests {
  // lusid1/pkg2zip#14: find_pbp_sfo cleared 16 bytes of main's 10-byte disc id buffer, and
  // parse_sfo_content copied DISC_ID into it without any bound.
  @Test("PSP disc id from EBOOT.PBP is bounded to the caller's buffer")
  func oversizedPBPDiscIDIsTruncated() async throws {
    let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NPSPkg2ZipDiscIDTest-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workspace) }

    // One PSP item, USRDIR/CONTENT/EBOOT.PBP, whose PARAM.SFO has a 40-character DISC_ID.
    // The whole fixture is encrypted once in CTR mode, which matches the per-region
    // decryption because every region starts on a 16-byte block.
    let harness = workspace.appendingPathComponent("discid-probe.c")
    try """
    #define main pkg2zip_command_main
    #include "pkg2zip.c"
    #undef main
    #include <fcntl.h>
    #include <stdint.h>
    #include <stdio.h>
    #include <unistd.h>

    int main(int argc, char** argv) {
        int long_name = argc > 1 && strcmp(argv[1], "long-name") == 0;
        static uint8_t pkg[4096];
        const char* name = "USRDIR/CONTENT/EBOOT.PBP";
        const char* disc = "ULUS10041ABCDEFGHIJKLMNOPQRSTUVWXYZ012345";
        uint32_t name_size = long_name ? ZIP_MAX_FILENAME : (uint32_t)strlen(name);
        uint32_t sfo_size = 120;
        uint8_t* eboot = pkg + 0x40;
        uint8_t* sfo = eboot + 0x28;
        set32le(sfo + 0, 0x46535000); set32le(sfo + 8, 52); set32le(sfo + 12, 68);
        set32le(sfo + 16, 2); set16le(sfo + 20, 0); set32le(sfo + 32, 0);
        set16le(sfo + 36, 6); set32le(sfo + 48, 8);
        memcpy(sfo + 52, "TITLE\\0DISC_ID", 14);
        memcpy(sfo + 68, "Probe", 6);
        memcpy(sfo + 76, disc, strlen(disc) + 1);
        memcpy(eboot, "\\0PBP", 4);
        set32le(eboot + 8, 0x28); set32le(eboot + 12, 0x28 + sfo_size);
        set32be(pkg + 0, 0x20); set32be(pkg + 4, name_size);
        set64be(pkg + 8, 0x40); set64be(pkg + 16, 0x28 + sfo_size);
        pkg[24] = 0x90;
        memcpy(pkg + 0x20, name, strlen(name));
        uint8_t raw_key[16] = {0};
        uint8_t iv[16] = {0};
        aes128_key key;
        aes128_init(&key, raw_key);
        aes128_ctr_xor(&key, iv, 0, pkg, sizeof(pkg));
        int fd = open("pkg-discid.fixture", O_RDWR | O_CREAT | O_TRUNC, 0600);
        if (fd < 0 || pwrite(fd, pkg, sizeof(pkg), 0) != (ssize_t)sizeof(pkg)) return 2;
        char discid[10];
        find_pbp_sfo(&key, &key, iv, (sys_file)(intptr_t)fd, sizeof(pkg), 0, 0, 1, \
    discid, sizeof(discid));
        close(fd);
        printf("discid=[%s]\\n", discid);
        return 0;
    }
    """.write(to: harness, atomically: true, encoding: .utf8)

    let results = try await runPkg2ZipProbe(
      harness: harness,
      named: "discid-probe",
      runs: [[], ["long-name"]],
      workspace: workspace
    )
    let discID = results[0]
    let longName = results[1]
    #expect(discID.status == 0, "\(discID.output)")
    #expect(discID.output.contains("discid=[ULUS10041]\n"))
    #expect(!discID.output.contains("AddressSanitizer"))

    #expect(longName.status != 0)
    #expect(longName.output.contains("very long name"))
    #expect(!longName.output.contains("AddressSanitizer"))
  }
}

extension Pkg2ZipPathSafetyTests {
  private func makeProbeWorkspace(_ label: String) throws -> URL {
    let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NPSPkg2Zip\(label)Test-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    return workspace
  }

  @Test("pkg2zip header and PARAM.SFO parsing stay inside their buffers")
  func headerAndSFOParsingStayInBounds() async throws {
    let workspace = try makeProbeWorkspace("Header")
    defer { try? FileManager.default.removeItem(at: workspace) }
    let harness = workspace.appendingPathComponent("header-probe.c")
    try """
    #define main pkg2zip_command_main
    #include "pkg2zip.c"
    #undef main
    #include <fcntl.h>
    #include <stdio.h>
    #include <unistd.h>

    // ps3-title: content type 1 header whose title id field runs to the end of the
    // header. item-count: item_count * 32 wraps to 0 in 32 bits. sfo-key: the last
    // sfo key has no terminator inside the sfo data.
    int main(int argc, char** argv) {
        if (argc != 2) return 64;
        if (strcmp(argv[1], "sfo-key") == 0) {
            uint32_t size = 20 + 16 + 5;
            uint8_t* sfo = calloc(1, size);
            if (sfo == NULL) return 2;
            set32le(sfo, 0x46535000); set32le(sfo + 8, 36); set32le(sfo + 12, size);
            set32le(sfo + 16, 1);
            memcpy(sfo + 36, "TITLE", 5);
            char title[SFO_STRING_SIZE] = {0};
            parse_sfo_content(sfo, size, NULL, title, NULL, NULL, NULL, NULL, 0);
            printf("title=[%s]\\n", title);
            return 0;
        }
        static uint8_t pkg[0x200];
        set32be(pkg, 0x7f504b47);
        set32be(pkg + 8, 0x100);
        set32be(pkg + 12, 1);
        set64be(pkg + 32, 0x100);
        set32be(pkg + 0x100, 2); set32be(pkg + 0x104, 8);
        if (strcmp(argv[1], "ps3-title") == 0) {
            memset(pkg + 0x37, 'A', 0x100 - 0x37);
            set32be(pkg + 0x108, 1);
            set64be(pkg + 32, 0x200);
        } else if (strcmp(argv[1], "item-count") == 0) {
            set32be(pkg + 20, 0x08000000);
            set32be(pkg + 0x108, 0x15);
        } else {
            return 64;
        }
        int fd = open("header.pkg", O_RDWR | O_CREAT | O_TRUNC, 0600);
        if (fd < 0 || write(fd, pkg, sizeof(pkg)) != (ssize_t)sizeof(pkg)) return 2;
        close(fd);
        char* args[] = { "pkg2zip", "-l", "header.pkg", NULL };
        return pkg2zip_command_main(3, args);
    }
    """.write(to: harness, atomically: true, encoding: .utf8)

    let results = try await runPkg2ZipProbe(
      harness: harness,
      named: "header-probe",
      runs: [["ps3-title"], ["item-count"], ["sfo-key"]],
      workspace: workspace
    )
    let title = String(repeating: "A", count: 0x100 - 0x37)
    #expect(results[0].status == 0, "\(results[0].output)")
    #expect(results[0].output == "\(title) [AAAAAAAAA] [UNK] [PSX].zip\n")
    #expect(results[1].status != 0)
    #expect(results[1].output.contains("ERROR: pkg file is too small"))
    #expect(results[2].status != 0)
    #expect(results[2].output.contains("ERROR: cannot find title from sfo file"))
    #expect(results.allSatisfy { !$0.output.contains("AddressSanitizer") })
  }

  @Test("PSP EDAT, theme and KEYS.BIN headers must lie inside their package item")
  func pspItemHeadersAreBoundedByItemSize() async throws {
    let workspace = try makeProbeWorkspace("PSPItem")
    defer { try? FileManager.default.removeItem(at: workspace) }
    let harness = workspace.appendingPathComponent("psp-item-probe.c")
    try """
    #define main pkg2zip_command_main
    #include "pkg2zip.c"
    #undef main
    #include <fcntl.h>
    #include <stdio.h>
    #include <unistd.h>

    // Each mode points a PSP helper at a header offset that lies past the item.
    int main(int argc, char** argv) {
        if (argc != 2) return 64;
        static uint8_t pkg[4096];
        uint64_t item_size;
        if (strcmp(argv[1], "edat") == 0) {
            pkg[0xC] = 0xF0;
            item_size = 0x130;
        } else if (strcmp(argv[1], "theme") == 0) {
            pkg[0xC] = 0x70;
            item_size = 0x100;
        } else if (strcmp(argv[1], "keys") == 0) {
            memcpy(pkg, "\\0PBP", 4);
            set32le(pkg + 0x24, 0xFFFFFFF0);
            item_size = 0x400;
        } else {
            return 64;
        }
        uint8_t raw_key[16] = {0};
        uint8_t iv[16] = {0};
        aes128_key key;
        aes128_init(&key, raw_key);
        aes128_ctr_xor(&key, iv, 0, pkg, sizeof(pkg));
        int fd = open("psp-item.fixture", O_RDWR | O_CREAT | O_TRUNC, 0600);
        if (fd < 0 || pwrite(fd, pkg, sizeof(pkg), 0) != (ssize_t)sizeof(pkg)) return 2;
        sys_file* file = (sys_file*)(intptr_t)fd;
        out_begin("unused", 0);
        if (strcmp(argv[1], "edat") == 0) {
            unpack_psp_edat("out.edat", &key, iv, file, 0, 0, item_size);
        } else if (strcmp(argv[1], "theme") == 0) {
            char title[SFO_STRING_SIZE] = {0};
            get_psp_theme_title(title, &key, iv, file, 0, 0, item_size);
        } else {
            unpack_keys_bin("KEYS.BIN", &key, iv, file, 0, 0, item_size);
        }
        printf("no error\\n");
        return 0;
    }
    """.write(to: harness, atomically: true, encoding: .utf8)

    let results = try await runPkg2ZipProbe(
      harness: harness,
      named: "psp-item-probe",
      runs: [["edat"], ["theme"], ["keys"]],
      workspace: workspace
    )
    let expected = [
      "ERROR: EDAT file is to short!", "ERROR: PSP theme file is too short!",
      "ERROR: eboot file is to short!",
    ]
    for (result, message) in zip(results, expected) {
      #expect(result.status != 0)
      #expect(result.output.contains(message), "\(result.output)")
      #expect(!result.output.contains("AddressSanitizer"))
    }
  }

  @Test("Background-download task folders skip symbolic links and stop at the limit or on error")
  func backgroundDownloadTaskSearchIsBounded() async throws {
    let workspace = try makeProbeWorkspace("BackgroundDownload")
    let fileManager = FileManager.default
    // Readable but not searchable: the O_NOFOLLOW walk opens it, fstatat fails with EACCES.
    let denied = workspace.appendingPathComponent("denied/t", isDirectory: true)
    try fileManager.createDirectory(at: denied, withIntermediateDirectories: true)
    try fileManager.setAttributes([.posixPermissions: 0o400], ofItemAtPath: denied.path)
    defer {
      try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
      try? fileManager.removeItem(at: workspace)
    }
    let freeTasks = workspace.appendingPathComponent("free/t", isDirectory: true)
    try fileManager.createDirectory(at: freeTasks, withIntermediateDirectories: true)
    try fileManager.createSymbolicLink(
      atPath: freeTasks.appendingPathComponent("00000001").path,
      withDestinationPath: workspace.appendingPathComponent("missing-target").path
    )
    for task in 1...3 {
      try fileManager.createDirectory(
        at: workspace.appendingPathComponent("full/t/0000000\(task)", isDirectory: true),
        withIntermediateDirectories: true
      )
    }
    let harness = workspace.appendingPathComponent("bgdl-probe.c")
    try """
    #define PKG2ZIP_BGDL_TASK_MAX 3
    #define main pkg2zip_command_main
    #include "pkg2zip.c"
    #undef main
    #include <stdio.h>

    int main(int argc, char** argv) {
        if (argc != 2) return 64;
        printf("task=%u\\n", next_bgdl_task(argv[1]));
        return 0;
    }
    """.write(to: harness, atomically: true, encoding: .utf8)

    let results = try await runPkg2ZipProbe(
      harness: harness,
      named: "bgdl-probe",
      runs: [["free/t"], ["full/t"], ["denied/t"]],
      workspace: workspace
    )
    #expect(results[0].status == 0, "\(results[0].output)")
    #expect(results[0].output == "task=2\n")
    #expect(results[1].status != 0)
    #expect(
      results[1].output.contains("ERROR: no free background download task folder in 'full/t'")
    )
    if getuid() != 0 {
      #expect(results[2].status != 0)
      let message = "ERROR: cannot inspect output folder 'denied/t/00000001'"
      #expect(results[2].output.contains(message))
    }
    #expect(results.allSatisfy { !$0.output.contains("AddressSanitizer") })
    let target = workspace.appendingPathComponent("missing-target")
    #expect(!fileManager.fileExists(atPath: target.path))
  }

  @Test("Vita digs.bin becomes body.bin and cert.bin keeps its name without duplicate ZIP entries")
  func vitaPackageSignatureFilesDoNotCollide() async throws {
    let workspace = try makeProbeWorkspace("VitaBody")
    defer { try? FileManager.default.removeItem(at: workspace) }
    let harness = workspace.appendingPathComponent("vita-body-probe.c")
    try """
    #define main pkg2zip_command_main
    #include "pkg2zip.c"
    #undef main
    #include <fcntl.h>
    #include <stdio.h>
    #include <unistd.h>

    // A Vita application package whose sce_sys/package holds cert.bin (first) and
    // digs.bin. Items are stored at enc_offset 0x400; digs.bin and cert.bin are
    // copied without decryption, so their output equals the fixture bytes.
    int main(int argc, char** argv) {
        if (argc != 2) return 64;
        static uint8_t pkg[0x520];
        uint8_t* sfo = pkg + 0x200;
        uint8_t* enc = pkg + 0x400;
        set32be(pkg, 0x7f504b47);
        set32be(pkg + 8, 0x100); set32be(pkg + 12, 3); set32be(pkg + 20, 2);
        set64be(pkg + 24, sizeof(pkg)); set64be(pkg + 32, 0x400); set64be(pkg + 40, 0x100);
        memset(pkg + 0x70, 0x5A, 16);
        pkg[0xe7] = 2;
        set32be(pkg + 0x100, 2); set32be(pkg + 0x104, 8); set32be(pkg + 0x108, 0x15);
        set32be(pkg + 0x110, 13); set32be(pkg + 0x114, 8);
        set32be(pkg + 0x118, 0); set32be(pkg + 0x11C, 0x100);
        set32be(pkg + 0x120, 14); set32be(pkg + 0x124, 8);
        set32be(pkg + 0x128, 0x200); set32be(pkg + 0x12C, 160);
        set32le(sfo, 0x46535000); set32le(sfo + 8, 68); set32le(sfo + 12, 96);
        set32le(sfo + 16, 3);
        set16le(sfo + 20, 0); set32le(sfo + 32, 0);
        set16le(sfo + 36, 6); set32le(sfo + 48, 16);
        set16le(sfo + 52, 17); set32le(sfo + 64, 56);
        memcpy(sfo + 68, "TITLE\\0CONTENT_ID\\0CATEGORY", 26);
        memcpy(sfo + 96, "Probe Game", 11);
        memcpy(sfo + 112, "UP0000-PCSE00000_00-0000000000000000", 37);
        memcpy(sfo + 152, "gd", 3);
        const char* names[2] = { "sce_sys/package/cert.bin", "sce_sys/package/digs.bin" };
        for (int i = 0; i < 2; i++) {
            uint8_t* item = enc + i * 32;
            set32be(item, 0x40 + i * 0x20); set32be(item + 4, (uint32_t)strlen(names[i]));
            set64be(item + 8, 0x80 + i * 0x10); set64be(item + 16, 16);
            item[27] = 3;
            memcpy(enc + 0x40 + i * 0x20, names[i], strlen(names[i]));
            memcpy(enc + 0x80 + i * 0x10, i == 0 ? "CERT-DATA-000000" : "DIGS-DATA-111111", 16);
        }
        memset(pkg + 0x500, 'T', 0x20);
        uint8_t main_key[16];
        aes128_key vita_key;
        aes128_init(&vita_key, pkg_vita_2);
        aes128_ecb_encrypt(&vita_key, pkg + 0x70, main_key);
        aes128_key key;
        aes128_init(&key, main_key);
        aes128_ctr_xor(&key, pkg + 0x70, 0, enc, 0x100);
        int fd = open("vita.pkg", O_RDWR | O_CREAT | O_TRUNC, 0600);
        if (fd < 0 || write(fd, pkg, sizeof(pkg)) != (ssize_t)sizeof(pkg)) return 2;
        close(fd);
        if (strcmp(argv[1], "extract") == 0) {
            char* args[] = { "pkg2zip", "-x", "vita.pkg", NULL };
            pkg2zip_command_main(3, args);
            return 0;
        }
        char* args[] = { "pkg2zip", "vita.pkg", NULL };
        pkg2zip_command_main(2, args);
        return 0;
    }
    """.write(to: harness, atomically: true, encoding: .utf8)

    let results = try await runPkg2ZipProbe(
      harness: harness,
      named: "vita-body-probe",
      runs: [["extract"], ["zip"]],
      workspace: workspace
    )
    for result in results {
      #expect(result.status == 0, "\(result.output)")
      #expect(result.output.contains("renaming sce_sys/package/digs.bin to body.bin"))
      #expect(!result.output.contains("renaming sce_sys/package/cert.bin"))
      #expect(!result.output.contains("AddressSanitizer"))
    }

    let fixture = try Data(contentsOf: workspace.appendingPathComponent("vita.pkg"))
    let package = workspace.appendingPathComponent("app/PCSE00000/sce_sys/package")
    #expect(
      try Data(contentsOf: package.appendingPathComponent("body.bin")) == fixture[0x490..<0x4A0]
    )
    #expect(
      try Data(contentsOf: package.appendingPathComponent("cert.bin")) == fixture[0x480..<0x490]
    )

    let listing = try await runProcess(
      executable: URL(fileURLWithPath: "/usr/bin/zipinfo"),
      arguments: ["-1", "Probe Game [PCSE00000] [USA].zip"],
      currentDirectory: workspace
    )
    let names = listing.output.split(separator: "\n").map(String.init)
    #expect(listing.status == 0, "\(listing.output)")
    #expect(Set(names).count == names.count, "\(names)")
    #expect(names.contains("app/PCSE00000/sce_sys/package/body.bin"))
    #expect(names.contains("app/PCSE00000/sce_sys/package/cert.bin"))
  }
}

/// Compiles a harness that includes `pkg2zip.c` together with the other pkg2zip sources
/// under AddressSanitizer and runs it in `workspace`.
private func runPkg2ZipProbe(
  harness: URL,
  named name: String,
  arguments: [String] = [],
  workspace: URL
) async throws -> (status: Int32, output: String) {
  let results = try await runPkg2ZipProbe(
    harness: harness,
    named: name,
    runs: [arguments],
    workspace: workspace
  )
  return results[0]
}

/// Compiles the harness once and runs it once per entry in `runs`, in order.
private func runPkg2ZipProbe(
  harness: URL,
  named name: String,
  runs: [[String]],
  workspace: URL
) async throws -> [(status: Int32, output: String)] {
  let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let sourceDirectory = packageRoot.appendingPathComponent("Sources/CPkg2Zip", isDirectory: true)
  let cFiles = try FileManager.default.contentsOfDirectory(
    at: sourceDirectory,
    includingPropertiesForKeys: nil
  ).filter { $0.pathExtension == "c" && $0.lastPathComponent != "pkg2zip.c" }.sorted {
    $0.lastPathComponent < $1.lastPathComponent
  }
  func compileProbe(named name: String, sanitizerFlags: [String]) async throws -> URL {
    let executable = workspace.appendingPathComponent(name)
    let compile = try await runProcess(
      executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
      arguments: ["clang", "-std=c99", "-D_GNU_SOURCE", "-DNPS_PKG2ZIP_PORTABLE_ONLY"]
        + sanitizerFlags + ["-O1", "-g", "-I", sourceDirectory.path, harness.path]
        + cFiles.map(\.path) + ["-o", executable.path],
      currentDirectory: workspace
    )
    try #require(compile.status == 0, "pkg2zip probe \(name) did not compile: \(compile.output)")
    return executable
  }

  var probe = try await compileProbe(named: name, sanitizerFlags: ["-fsanitize=address"])
  var instrumented = true
  var results: [(status: Int32, output: String)] = []
  for arguments in runs {
    do {
      results.append(
        try await runProcess(
          executable: probe,
          arguments: arguments,
          currentDirectory: workspace,
          timeout: 30
        )
      )
    } catch is ProcessTimedOut where instrumented {
      // Some sanitizer runtimes deadlock while initializing on a newer macOS
      // (Xcode 16.3's ASan on macOS 27 spins in AsanInitInternal before main).
      // Rerun the probe uninstrumented; a real hang in pkg2zip times out
      // again and fails the test.
      probe = try await compileProbe(named: "\(name)-plain", sanitizerFlags: [])
      instrumented = false
      results.append(
        try await runProcess(
          executable: probe,
          arguments: arguments,
          currentDirectory: workspace,
          timeout: 30
        )
      )
    }
  }
  return results
}

private struct ProcessTimedOut: Error {}

/// Output goes to a file rather than a pipe so a chatty child cannot block on a
/// full pipe buffer, and a child that never exits is killed after `timeout`.
/// The wait runs on a GCD queue so it never holds a cooperative-pool thread.
private func runProcess(
  executable: URL,
  arguments: [String],
  currentDirectory: URL,
  timeout: TimeInterval = 120
) async throws -> (status: Int32, output: String) {
  try await BlockingWork.run {
    try runProcessBlocking(
      executable: executable,
      arguments: arguments,
      currentDirectory: currentDirectory,
      timeout: timeout
    )
  }
}

private func runProcessBlocking(
  executable: URL,
  arguments: [String],
  currentDirectory: URL,
  timeout: TimeInterval
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
