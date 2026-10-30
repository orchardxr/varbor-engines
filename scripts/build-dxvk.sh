#!/usr/bin/env bash
# Build an entry's DXVK (CrossOver's fork + ARM64EC fixes; scripts/fetch-sources.sh first) for ARM64EC.
#   scripts/build-dxvk.sh <id>
# Output: build/<id>/dxvk/install/aarch64-windows/{d3d9,d3d10,d3d10_1,d3d10core,d3d11}.dll, the set CrossOver ships
# for x86_64 (its d3d11 runs on Wine's dxgi, so no dxgi.dll), marked as Wine builtins like CrossOver's since lib/dxvk
# is a builtin search dir. x86_64/i386 are not built: our patches only add ARM64EC, so they would equal stock.
# Needs glslangValidator, meson, ninja on PATH.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
id="${1:?usage: $0 <id>}"
SRC="$BUILD/$id/src/dxvk"
OUT="$BUILD/$id/dxvk"
[[ -f "$SRC/meson.build" ]] || die "no $SRC (scripts/fetch-sources.sh $id dxvk)"
mf get "$id" dxvk.arches | grep -qx arm64ec || die "$id builds no ARM64EC DXVK"
command -v glslangValidator > /dev/null || die "no glslangValidator"
mkdir -p "$OUT"
eval "$("$ROOT/scripts/toolchains.sh" "$id" llvm-mingw wine-arm64ec)"
winebuild="$WINE_ARM64EC/bin/winebuild"

triple=arm64ec-w64-mingw32
cross="$OUT/cross-arm64ec.txt"
cat > "$cross" <<EOF
[binaries]
c = '$LLVM_MINGW/bin/$triple-clang'
cpp = '$LLVM_MINGW/bin/$triple-clang++'
ar = '$LLVM_MINGW/bin/$triple-ar'
strip = '$LLVM_MINGW/bin/$triple-strip'
windres = '$LLVM_MINGW/bin/$triple-windres'

[properties]
needs_exe_wrapper = true

[host_machine]
system = 'windows'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF

bdir="$OUT/build-arm64ec"
log="$LOGS/$id-dxvk-arm64ec.log"
rm -rf "$bdir" "$OUT/stage"
# patch 0002 points meson at build/implib for the import libs DXVK only ships for x86/x86_64
mkdir -p "$bdir/implib"
printf 'LIBRARY vulkan-1.dll\nEXPORTS\n  vkGetInstanceProcAddr\n' > "$bdir/implib/vulkan-1.def"
"$LLVM_MINGW/bin/llvm-dlltool" -m arm64ec -d "$bdir/implib/vulkan-1.def" -l "$bdir/implib/libvulkan-1.a"
"$LLVM_MINGW/bin/llvm-dlltool" -m arm64ec -d "$SRC/lib/libd3dcompiler_43.def" -l "$bdir/implib/libd3dcompiler_43.a"

echo "==> DXVK arm64ec $(git -C "$SRC" describe --always), log $log"
{
	meson setup --cross-file "$cross" --buildtype release -Dstrip=true -Denable_tests=false -Denable_dxgi=false \
		--prefix "$OUT/stage" --bindir aarch64-windows --libdir aarch64-windows "$bdir" "$SRC" &&
		meson compile -C "$bdir" && meson install -C "$bdir"
} > "$log" 2>&1 || { tail -30 "$log"; exit 1; }

dst="$OUT/install/aarch64-windows"
rm -rf "$dst"
mkdir -p "$dst"
for d in d3d9 d3d10 d3d10_1 d3d10core d3d11; do
	cp "$OUT/stage/aarch64-windows/$d.dll" "$dst/"
	"$winebuild" --builtin "$dst/$d.dll"
done
file "$dst"/*.dll | sed "s|$OUT/||"
