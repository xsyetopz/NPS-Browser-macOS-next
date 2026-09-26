# pkg2zip source

This directory vendors source from
[lusid1/pkg2zip](https://github.com/lusid1/pkg2zip), the maintained fork of the
archived [mmozeiko/pkg2zip](https://github.com/mmozeiko/pkg2zip). The vendored
revision is `master` at `6ee3df57eef2521ff38542a70500794937974180` (2026-08-04),
which is newer than the fork's latest release, 2.6 (`e9cd40c`, released
2024-06-29). The previous copy was mmozeiko revision
`9222c4e00235dfe7914e9db0cc352da07e63d9f9` (2018-07-15). The included `LICENSE`
is the Unlicense, dedicating this software to the public domain, and is
unchanged in the fork.

Only the C sources and headers are vendored. The upstream x86-only AES-NI and
PCLMUL files (`pkg2zip_aes_x86.c`, `pkg2zip_crc32_x86.c`) are intentionally
omitted, and `NPS_PKG2ZIP_PORTABLE_ONLY`, defined by `Package.swift`, selects
the upstream generic fallback implementations, so the package builds the
portable C code for each SwiftPM target architecture.

The fork supports Vita application, DLC, patch, theme and PSM packages, and PSP,
PSP DLC, PSP theme and PSX packages. It also extracts PSX games packaged for the
PS3 store (package content type 1). It does **not** extract PS3 games. Keep the
executable isolated as a helper process because its error path calls `exit()`.

## Local modifications

- `pkg2zip_aes.c` and `pkg2zip_crc32.c` skip the x86 dispatch when
  `NPS_PKG2ZIP_PORTABLE_ONLY` is defined.
- The output layer (`pkg2zip_sys.c`, `pkg2zip_out.c`) rejects empty, absolute
  and traversal paths, backslashes, colons and control characters in every
  output path, including the fork's `out_add_parent`. On POSIX it creates
  folders and files one component at a time beneath the extraction root with
  `O_NOFOLLOW`, so symbolic links are never followed, and it never overwrites an
  existing file. `out_add_parent` also rejects a parent path longer than its
  buffer.
- Package item names longer than the fixed filename buffer are rejected before
  they are read in `find_psp_sfo`, `find_pbp_sfo` and the extraction loop, and
  item ranges are checked against the package size without integer overflow
  (`pkg_range_is_valid`).
- [lusid1/pkg2zip#14](https://github.com/lusid1/pkg2zip/issues/14):
  `find_pbp_sfo` cleared 16 bytes of `main`'s 10-byte `discid` buffer; the fork
  shrank the clear to 10 bytes, but `parse_sfo_content` still copied `DISC_ID`
  into the buffer without a bound. `find_pbp_sfo` now takes the buffer size,
  clears and fills only that many bytes, and truncates the disc id. Its
  PARAM.SFO read also allows for the unaligned start of the SFO inside
  `EBOOT.PBP`, which could overrun the 16 KiB buffer by up to 15 bytes.
- `parse_sfo_content` copies every SFO string with a bound: the 256-byte buffers
  from `main` (`SFO_STRING_SIZE`) no longer overflow on long values or on a
  title full of colons, value offsets outside the SFO data are rejected, and an
  empty `PSP2_DISP_VER` can no longer write before its buffer.
- `parse_sfo_content` compares SFO keys without reading past the SFO data and
  requires the 20-byte header and whole 16-byte index entries.
- `main` zero-initialises its title, category, content, version, disc id and
  RIF buffers, so a package without `PARAM.SFO` (or without some keys) reads no
  uninitialised memory.
- The PS3-hosted PSX title (lusid1's `sprintf(title, "%s", pkg_header + 0x37)`)
  is bounded to both the header and the title buffer.
- The RIF content id at `rif + 0x10` (and `+ 0x50` for PSM) is printed and used
  in the PocketStation licence path only up to its 0x30-byte field
  (`RIF_CONTENT_ID_SIZE`).
- `item_count * 32` and each item's table offset are computed in 64 bits, the
  whole item table must lie inside the package, and the Vita `tail.bin` range is
  checked before it is copied.
- `get_psp_theme_title` (which now takes the item size), `unpack_psp_edat` and
  `unpack_keys_bin` check every header and data offset they read against the
  item size, in 64-bit arithmetic.
- `sys_test_dir` resolves the path beneath the extraction root with the same
  `O_NOFOLLOW` walk as the output layer and checks the last component with
  `fstatat(..., AT_SYMLINK_NOFOLLOW)`. Any existing entry, including a symbolic
  link, counts as taken, and errors other than a missing entry are fatal. The
  Vita theme background-download folder search (`next_bgdl_task`) stops after
  `PKG2ZIP_BGDL_TASK_MAX` (0xFFFF) folders with an error instead of spinning.
- lusid1 `ebd4ecf` renames `sce_sys/package/cert.bin` to `body.bin`, like
  `digs.bin`, for packages (such as the PS Suite and PSM runtime packages in
  mmozeiko/pkg2zip#13) that ship `cert.bin` instead of `digs.bin`. A package
  with both files wrote `body.bin` twice. Now `digs.bin` always becomes
  `body.bin`, whatever the item order, and `cert.bin` is then kept verbatim
  under its own name; a package with only `cert.bin` behaves as lusid1 intends.
- The ZIP writer records every entry name: a folder added twice is written once
  (lusid1's `out_add_parent` added each file's parent folder again), and a file
  added twice is an error, matching unzipped output, which never overwrites.
- `rif_load` reports an error instead of dereferencing a null `FILE*` when the
  RIF file cannot be opened.

The sources build without warnings under `-Wall -Wextra -Werror` with Apple
clang and GCC 16 (`-O2 -D_FORTIFY_SOURCE=2`).
