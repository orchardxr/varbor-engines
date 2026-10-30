# Sourced by the scripts. Layout:
#   build/toolchains            llvm-mingw, LLVM 15, Wine toolchains (scripts/toolchains.sh)
#   build/src/{dxmt,dxvk}       upstream clones (shared by all entries)
#   build/<id>/src/{dxmt,dxvk}  per-entry worktrees: the manifest commit with our patches as commits on top
#   build/<id>/{dxmt,dxvk}      meson build dirs, staging, install
#   build/logs                  build logs
#   dist/                       release tarballs and metadata
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="${VARBOR_BUILD:-$ROOT/build}"
TC="${VARBOR_TOOLCHAINS:-$BUILD/toolchains}"
LOGS="$BUILD/logs"
DIST="${VARBOR_DIST:-$ROOT/dist}"
mkdir -p "$BUILD" "$TC" "$LOGS"

die() { echo "$(basename "$0"): $*" >&2; exit 1; }
mf() { python3 -I "$ROOT/scripts/lib/manifest.py" "$@"; }

# Pinned toolchains; the environment overrides each (LLVM_MINGW, LLVM15_ARM64, LLVM15_X86_64, WINE_ARM64EC, WINE_X86_64)
LLVM_MINGW_VERSION="${LLVM_MINGW_VERSION:-20260922}"
LLVM_MINGW_NAME="llvm-mingw-$LLVM_MINGW_VERSION-ucrt-macos-universal"

engine_version_tag() {
	local id="$1" lib="$2" base
	base="$(mf get "$id" "$lib.stock.version")"
	[[ $lib == dxmt ]] && base="$(mf get "$id" dxmt.describe)"
	echo "$base-varbor.$(mf get "$id" revision)"
}
