# varbor-engines

VarboR's patched graphics engines (DXMT, DXVK) for each CrossOver build, published as GitHub releases.

VarboR does not ship engines. At run time it finds the user's CrossOver / NotProton runners, reads each runner's
CrossOver version, and downloads the release made for that exact build. That way VarboR does not depend on any one
CrossOver version, and a new CrossOver build only needs a new entry here.

## Why per CrossOver build

- **DXMT**: CrossOver ships a DXMT built from its own branch. Our patch (`IDXMTInteropSurface` / `IDXMTInteropDevice`,
  which gives an in-process native runtime the game's own `MTLTexture`) has to go on the DXMT that build ships,
  because DXMT's unix side `winemetal.so` is tied to CrossOver's Wine (see [Wine coupling](#dxmt-and-crossovers-wine)).
- **DXVK**: CrossOver ships its DXVK fork (`cxaddon-1.10.3`) for x86_64/i386 only. FEX runners need an ARM64EC build
  (`lib/dxvk/aarch64-windows`), which we build from CodeWeavers' published sources plus ARM64EC fixes.

## Layout

```
builds.json                       the manifest: one entry per CrossOver build
patches/dxmt/<base describe>/     DXMT patches, by the DXMT commit they apply to (v0.80-247-gfb451568, v0.72)
patches/dxvk/cxaddon-1.10.3/      0001 = CrossOver's DXVK fork as a diff on upstream v1.10.3; 0002 = ARM64EC fixes
licenses/                         license texts for code linked into the binaries that the sources don't carry
scripts/detect-runner.sh          print a runner's CrossOver/Wine/DXMT/DXVK versions and its manifest entry
scripts/build.sh <id>             fetch-sources + build-dxmt + build-dxvk (if the entry has a DXVK build) + package
scripts/fetch-sources.sh <id>     build/<id>/src/{dxmt,dxvk}: manifest commit + patches as commits + version tag
scripts/build-dxmt.sh <id>        DXMT for the entry's arches: arm64ec, x86_64, i386
scripts/build-dxvk.sh <id>        ARM64EC DXVK
scripts/package.sh <id>           dist/: release tarball, source tarball, metadata.json, SHA256SUMS
scripts/toolchains.sh             llvm-mingw, LLVM 15, Wine toolchains (fetched/built into build/toolchains)
scripts/wine-unix-libs.sh         ntdll.so/winemac.so for winemetal.so: a runner's, or stubs (CI)
```

## Manifest (`builds.json`)

Top level:

| Key | Meaning |
|---|---|
| `schema` | manifest format version (1) |
| `release_tag` | tag pattern, `cx-{crossover.version}` |
| `detect` | where and how to read the versions from a runner (below) |
| `builds[]` | entries |

Entry:

| Key | Meaning |
|---|---|
| `id` | the CrossOver version, e.g. `27.0.0.41073` |
| `build` | whether CI builds and releases it; `build_note` says why not |
| `revision` | bumped when the same CrossOver build gets new engines (new patch, fix); VarboR re-downloads on change |
| `crossover.version` / `public_version` / `date` | `CX_VERSION`, `PUBLIC_VERSION` and date from `distversion.pyc` |
| `crossover.wine` | the Wine build id in the runner's `ntdll.so` (`wine-11.17-8910-g4683e69e153`) |
| `crossover.unix_arches`, `notproton_runners` | unix arches of the runner; NotProton runner dir names of this build |
| `sources` | CodeWeavers' sources tarball: name, sha256, public URL (null if not public) |
| `dxmt.stock` | the DXMT version string the runner ships, its arch dirs, and whether that commit is public |
| `dxmt.repo` / `commit` / `describe` | what we build: upstream repo and the commit (full sha) |
| `dxmt.submodules`, `patches`, `arches` | submodules to init, patches in order, arches to build (`arm64ec`, `x86_64`, `i386`) |
| `dxmt.meson_options` | extra `meson setup` options (v0.72 needs `-Dwine_builtin_dll=true`, later DXMT defaults to it) |
| `dxmt.toolchain` | LLVM ref; Wine toolchains whose import libs and winebuild the PE side uses |
| `dxmt.wine_unix` | what `winemetal.so` needs from CrossOver's Wine (below) |
| `dxvk.stock`, `repo`, `commit`, `describe`, `patches`, `patches_origin`, `arches` | the same for DXVK; no `repo` means no DXVK is built or shipped (`note` says why) |

### Detecting a runner

A runner is a CrossOver root (`CrossOver.app/Contents/SharedSupport/CrossOver`, or NotProton's
`runners/crossover-<build>[-fex]/CrossOver`). `detect` in the manifest gives the files and regexes:

- **CrossOver build**: `lib/python/distversion.pyc`. The first three strings in the marshalled module are
  `CX_VERSION`, `PUBLIC_VERSION`, date (e.g. `27.0.0.41073`, `20261015`, `2026/10/14`). `PUBLIC_VERSION` also names
  the sources tarball, `crossover-sources-<PUBLIC_VERSION>.tar.gz`.
- **Wine**: `wine-…` string in `lib/wine/<arch>-unix/ntdll.so`.
- **DXMT**: the `v0.80-279-g8f06be3`-style string in `lib/dxmt/<arch>-windows/d3d11.dll`.
- **DXVK**: the `cxaddon-1.10.3-1-25-g737aacd`-style string in `lib/dxvk/<arch>-windows/d3d11.dll`.

Our builds carry `-varbor.<revision>` on the base version, e.g. `v0.80-247-gfb451568-varbor.1` and
`cxaddon-1.10.3-1-25-g737aacd-varbor.1`, so VarboR (and DXMT/DXVK's own log lines) can tell them from stock.
`detect-runner.sh` reports such a runner (a clone with our engines) as `DXMT from varbor-engines (…)` rather than as
differing from stock.

```
$ scripts/detect-runner.sh            # all NotProton runners; or pass paths; --json for machine output
runner:     ~/Library/Application Support/notproton/runners/crossover-27.0.0.41073-fex
crossover:  27.0.0.41073 (public 20261015, 2026/10/14)
wine:       wine-11.17-8910-g4683e69e153 [aarch64,x86_64]
dxmt:       aarch64-windows  v0.80-279-g8f06be3
dxmt:       i386-windows     v0.80-279-g8f06be3
dxmt:       x86_64-windows   v0.80-279-g8f06be3
dxvk:       i386-windows     cxaddon-1.10.3-1-25-g737aacd
dxvk:       x86_64-windows   cxaddon-1.10.3-1-25-g737aacd
entry:      27.0.0.41073 (supported), release cx-27.0.0.41073
```

### Upstream versions

CrossOver's DXMT version string names a commit of CodeWeavers' DXMT branch, which need not be public. `commit` is the
public upstream commit we build, `stock.version` the string to detect the runner by; the manifest records both.

**27.0.0.41073** ships `v0.80-279-g8f06be3`: 32 commits past `fb451568` (`v0.80-247`). 8f06be3 is in no branch, tag
or PR of 3Shain/dxmt, and none of upstream's commits after fb451568 is in the shipped binaries under another hash:

- CodeWeavers' sources tarball for the build (`crossover-sources-20261015.tar`, `sources/dxmt`) is exactly
  fb451568 apart from `.gitmodules` URLs and `-marm64x` in `build-arm64ec.txt`.
- Upstream main has 20 commits between fb451568 and the build date (2026/10/14; 830eb419 … 186a2327, committed
  2026-10-05 to 10-12). Their string changes are missing from the shipped DLLs: a22700c7's
  `[CacheWriter] Failed to resolve cache path` (the binaries still have the old copy-paste `[CacheReader]` one) and
  186a2327's `map-on-default` warning.
- The other branch that reaches the right count, the DXIL work (PR 232, e94c312f + 17 commits = v0.80-279 on
  2026-10-09), adds dozens of `dxil: …` errors to `winemetal.so`'s airconv; the shipped `winemetal.so` has none.
- Strings, `DXMT_*` environment variables, config keys and PE exports of d3d11/dxgi/d3d10core/winemetal.dll match our
  fb451568 build one for one (besides our patch's `DXMT_INTEROP_TEXTURE_INFO`). Everything else that differs is the
  toolchain: CodeWeavers' Wine import libs (`__wine_load_unix_lib`, `LdrGetDllHandle`), an LLVM with zlib and
  without assertions in `winemetal.so`, and their code signature.

So the 32 commits are CodeWeavers-internal (packaging, merges) with no code change visible in the binaries, and
fb451568 stays the base. No later upstream commit is equivalent.

**26.3.0.39832** ships `v0.72-25-gf35d839`. f35d839 is not public, and the 26.3 sources tarball has no DXMT at all
(`sources/` holds dxvk, moltenvk, vkd3d, wine and others; none of its nested archives has DXMT either). The binaries
are a v0.72 maintenance branch, not main: they have upstream's later nvapi stubs (a60483b7, cffcdb47, f18b1c42:
`NvAPI_GPU_GetArchInfo`, `GetBusType`, `GetMemoryInfoEx`) but not `DXMT_SHADER_CACHE` (44c6fc57, 9 commits after
v0.72 on main). We build the public `v0.72` tag (3d8d2aa1) with two upstream build fixes for current toolchains
(e67727f2, 06065754) and our interop patch, ported: v0.72 has everything it needs (the immediate context's
`ID3D11Fence` Signal/Wait encode `MTLSharedEvent` signal/wait, the command queue's event and sequence id); only the
resource and context plumbing differs (no keyed mutex, `texture()` returns `Rc<Texture>`, no mip count on
`Texture`). Our i386 DLLs ship too, so 32-bit games and our `winemetal.so` always speak the same unix-call table.

### DXMT and CrossOver's Wine

DXMT's PE DLLs talk to `winemetal.so` over Wine's `__wine_unix_call`; they link only against Wine's import libs
(`libwinecrt0.a`, `libntdll.a`, `libdbghelp.a`) and are marked builtin with `winebuild`. That part takes the Wine
toolchains DXMT's CI uses (3Shain's wine-11.2 for ARM64EC, v8.16-3shain for x86_64).

`winemetal.so` is where CrossOver's Wine matters. It links `@rpath/ntdll.so` and `@rpath/winemac.so` (resolved to
the runner's `lib/wine/<arch>-unix`), binds `NtSetEvent` from ntdll.so, and looks up at run time
`macdrv_functions` (CrossOver's table: `get_win_data`, `release_win_data`, `macdrv_view_create_metal_view`,
`macdrv_view_get_metal_layer`, …) or those symbols directly. So it must be built for the runner's Wine and
winemac.drv: the struct layouts behind `macdrv_functions` and the window data are CrossOver's. `dxmt.wine_unix`
lists the link-time symbols and the looked-up ones.

`scripts/wine-unix-libs.sh` links against the runner's own `ntdll.so`/`winemac.so` when `CX_RUNNER` is set (local
builds), and otherwise against stub dylibs with the same install names that export only the listed symbols (CI,
which has no CrossOver). Both give the same load commands and bindings. LLVM 15 (DXMT's airconv) is linked
statically into `winemetal.so`.

## Releases

One release per buildable entry, tag `cx-<crossover version>`:

```
https://github.com/orchardxr/varbor-engines/releases/download/cx-<version>/metadata.json
https://github.com/orchardxr/varbor-engines/releases/download/cx-<version>/varbor-engines-cx-<version>.tar.gz
https://github.com/orchardxr/varbor-engines/releases/download/cx-<version>/varbor-engines-cx-<version>-src.tar.gz
https://github.com/orchardxr/varbor-engines/releases/download/cx-<version>/SHA256SUMS
```

`varbor-engines-cx-<version>.tar.gz`:

```
varbor-engines-cx-27.0.0.41073/
  metadata.json
  dxmt/aarch64-windows/{d3d11,dxgi,d3d10core,winemetal}.dll    ARM64EC (FEX runners)
  dxmt/aarch64-unix/winemetal.so
  dxmt/x86_64-windows/{d3d11,dxgi,d3d10core,winemetal}.dll     x86_64 (Rosetta runners)
  dxmt/x86_64-unix/winemetal.so
  dxvk/aarch64-windows/{d3d9,d3d10,d3d10_1,d3d10core,d3d11}.dll ARM64EC, marked builtin
  licenses/
```

`cx-26.3.0.39832` (Rosetta only) has `dxmt/x86_64-windows`, `dxmt/i386-windows` and `dxmt/x86_64-unix`, and no
`dxvk/`: the runner's stock x86_64/i386 DXVK is what it loads.

`metadata.json`:

```json
{
  "schema": 1,
  "id": "27.0.0.41073",
  "tag": "cx-27.0.0.41073",
  "revision": 1,
  "crossover": { "version": "27.0.0.41073", "public_version": "20261015", "wine": "wine-11.17-…", "unix_arches": ["aarch64", "x86_64"] },
  "dxmt": {
    "version": "v0.80-247-gfb451568-varbor.1",
    "stock_version": "v0.80-279-g8f06be3",
    "repo": "https://github.com/3Shain/dxmt.git", "commit": "fb4515…", "describe": "v0.80-247-gfb451568",
    "patches": [{ "file": "patches/dxmt/…/0001-d3d11-metal-interop.patch", "sha256": "…" }],
    "files": { "dxmt/aarch64-windows/d3d11.dll": "<sha256>", "…": "…" }
  },
  "dxvk": { "version": "cxaddon-1.10.3-1-25-g737aacd-varbor.1", "stock_version": "cxaddon-1.10.3-1-25-g737aacd", "…": "…" },
  "build": { "date": "…", "varbor_engines_commit": "…", "llvm_mingw": "20260922", "llvm": "llvmorg-15.0.7", "wine_unix_libs": "stub" },
  "licenses": { "…": "…" },
  "source": "varbor-engines-cx-27.0.0.41073-src.tar.gz"
}
```

### How VarboR uses it

1. For each runner, read `CX_VERSION` from `lib/python/distversion.pyc` (as `scripts/detect-runner.sh` does).
2. GET `…/releases/download/cx-<version>/metadata.json`. A 404 means the build is not supported (yet): leave the
   runner stock. Optionally check the runner's stock DXMT/DXVK strings against `dxmt.stock_version` /
   `dxvk.stock_version`; a mismatch means the runner was modified and should not be patched.
3. If `revision` is newer than what VarboR has cached, download the tarball, check it against `SHA256SUMS`, and each
   file against `metadata.files`.
4. Never write into the user's runner. Make an APFS clone of it (`cp -c -R`) and overlay the files into the clone's
   `CrossOver/lib/dxmt/<arch>-{windows,unix}/` and `CrossOver/lib/dxvk/aarch64-windows/` (whichever the release
   has). Everything else, including stock `nvapi64.dll`/`nvngx.dll`, the arches a release lacks and the x86_64/i386
   DXVK, stays as shipped. `CX_GRAPHICS_BACKEND`
   (`dxmt` default, or `dxvk`) picks the engine, as in stock CrossOver.
5. Record the installed `revision` and file hashes in the clone to detect staleness.

## Adding a CrossOver build

1. Install the build (NotProton runner or CrossOver.app) and run `scripts/detect-runner.sh <runner>`.
2. Get CodeWeavers' sources (`https://media.codeweavers.com/pub/crossover/source/crossover-sources-<public>.tar.gz`
   for releases, linked from <https://www.codeweavers.com/crossover/source>). Find the upstream DXMT commit
   `sources/dxmt` matches (hash the tree into a DXMT clone and diff against nearby commits), and diff `sources/dxvk`
   against upstream DXVK to see whether the existing DXVK patch still holds.
3. Add the entry. Rebase the DXMT patch if it doesn't apply, into `patches/dxmt/<new describe>/`.
4. `scripts/build.sh <id>` locally (with `CX_RUNNER=<runner>`), test in a runner clone, then run the workflow with
   `publish`.

## Building locally

Needs Xcode (with the Metal toolchain: `xcodebuild -downloadComponent MetalToolchain` on Xcode 26+), Homebrew
`meson ninja glslang cmake`, python3.

```sh
CX_RUNNER="$HOME/Library/Application Support/notproton/runners/crossover-27.0.0.41073-fex" \
  scripts/build.sh 27.0.0.41073
```

Prebuilt toolchains can be passed in to skip the LLVM builds: `LLVM_MINGW`, `LLVM15_ARM64`, `LLVM15_X86_64`,
`WINE_ARM64EC`, `WINE_X86_64` (see `scripts/toolchains.sh`).

## CI

`.github/workflows/build.yml` runs on `macos-15` (arm64): LLVM 15 for arm64 and x86_64 (cached), then a matrix over
the buildable manifest entries that builds and packages each, uploads the assets as an artifact, and with the
`publish` input of a manual run creates or updates the release `cx-<version>`.

What CI cannot do:

- Download CrossOver or its runners: winemetal.so links against stubs (above), and nothing is run.
- Download CrossOver Preview sources tarballs. Only release sources are public
  (`crossover-sources-26.3.0.tar.gz` is; `crossover-sources-20261015.tar.gz` is not). CI doesn't need them: the
  DXVK fork is committed as a patch and DXMT is fetched from upstream. They are only needed to make or check an entry.
- Test the engines: that needs a runner and a GPU session (VarboR's own tests).

## Licenses and credits

- **DXMT** by Feifan He for CodeWeavers, <https://github.com/3Shain/dxmt>: LGPL-2.1-or-later since after v0.80
  (earlier releases, v0.72 included, were MIT; `LICENSE.OLD`). The release tarball includes the base commit's
  `DXMT-LICENSE` (and `DXMT-COPYING.LIB`, `DXMT-LICENSE.OLD` where present); the `-src` tarball of each release holds
  the complete patched source the binaries were built from. Our DXMT patches are under the same license as the base.
- **DXVK** by Philip Rebohle, Joshua Ashton and contributors, <https://github.com/doitsujin/dxvk>: zlib/libpng
  license (`DXVK-LICENSE`).
- **CrossOver's DXVK changes** (`cxaddon-1.10.3`, `patches/dxvk/cxaddon-1.10.3/0001`) are by CodeWeavers, Inc.,
  taken from the CrossOver sources CodeWeavers publishes (<https://www.codeweavers.com/crossover/source>). They are
  under DXVK's license. CrossOver itself is CodeWeavers' product and is not distributed here.
- **LLVM** 15 (statically linked into `winemetal.so`): Apache-2.0 with LLVM exceptions (`LLVM-LICENSE.TXT`).
- The build scripts and manifest in this repo: MIT (`LICENSE`).
