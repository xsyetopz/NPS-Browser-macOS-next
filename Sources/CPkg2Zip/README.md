# pkg2zip source

This directory vendors source from [mmozeiko/pkg2zip](https://github.com/mmozeiko/pkg2zip),
upstream revision `9222c4e00235dfe7914e9db0cc352da07e63d9f9` (2018-07-15).
The upstream project is archived. Its included `LICENSE` is the Unlicense, dedicating
this software to the public domain.

The package builds the portable C implementation for each SwiftPM target architecture.
The upstream x86-only AES-NI and PCLMUL acceleration files are intentionally omitted;
`NPS_PKG2ZIP_PORTABLE_ONLY` selects the upstream generic fallback implementations.
The upstream tool supports Vita, PSP, and PSX package workflows. It does **not** support
PS3 package extraction. Its output layer is hardened locally to reject absolute and
traversal paths and to open output components beneath the extraction root without
following symlinks. Keep the executable isolated as a helper process because its error
path calls `exit()`.
