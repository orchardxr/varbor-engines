#!/usr/bin/env bash
# Build an entry's DXMT (scripts/fetch-sources.sh first) for its manifest arches, or the ones given.
#   scripts/build-dxmt.sh <id> [arm64ec] [x86_64] [i386]
# arm64ec  ARM64EC d3d11/dxgi/d3d10core/winemetal.dll (aarch64-windows: what x86_64 games load on FEX runners)
#          + aarch64-unix winemetal.so
# x86_64   x86_64-windows DLLs + x86_64-unix winemetal.so (Rosetta runners)
# i386     i386-windows DLLs (32-bit games under WoW64; they talk to the x86_64-unix winemetal.so)
# Output: build/<id>/dxmt/install/<arch>-{windows,unix}. Like CrossOver's build: plain ARM64EC (no -marm64x), no
# nvapi/nvngx. winemetal.so links against scripts/wine-unix-libs.sh (CX_RUNNER's libs, else stubs).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
id="${1:?usage: $0 <id> [arm64ec] [x86_64]}"
shift
archs=("$@")
if [[ ${#archs[@]} == 0 ]]; then
	while IFS= read -r a; do archs+=("$a"); done < <(mf get "$id" dxmt.arches)
fi
SRC="$BUILD/$id/src/dxmt"
OUT="$BUILD/$id/dxmt"
[[ -f "$SRC/meson.build" ]] || die "no $SRC (scripts/fetch-sources.sh $id dxmt)"
mkdir -p "$OUT"

eval "$("$ROOT/scripts/toolchains.sh" "$id" llvm-mingw)"

for arch in "${archs[@]}"; do
	case "$arch" in
	arm64ec)
		triple=arm64ec-w64-mingw32 winearch=aarch64 unixarch=aarch64
		eval "$("$ROOT/scripts/toolchains.sh" "$id" llvm-arm64 wine-arm64ec)"
		llvm="$LLVM15_ARM64" wine="$WINE_ARM64EC" ;;
	x86_64)
		triple=x86_64-w64-mingw32 winearch=x86_64 unixarch=x86_64
		eval "$("$ROOT/scripts/toolchains.sh" "$id" llvm-x86_64 wine-x86_64)"
		llvm="$LLVM15_X86_64" wine="$WINE_X86_64" ;;
	i386)
		triple=i686-w64-mingw32 winearch=i386 unixarch=x86_64
		eval "$("$ROOT/scripts/toolchains.sh" "$id" llvm-x86_64 wine-x86_64)"
		llvm="$LLVM15_X86_64" wine="$WINE_X86_64" ;;
	*) die "unknown arch $arch" ;;
	esac
	# A Wine install for meson: winebuild and import libs from the toolchain Wine, the unix libs from the runner/stubs
	prefix="$OUT/wine-$arch"
	unixlibs="$("$ROOT/scripts/wine-unix-libs.sh" "$id" "$unixarch")"
	rm -rf "$prefix"
	mkdir -p "$prefix/bin" "$prefix/lib/wine/$winearch-windows" "$prefix/lib/wine/$unixarch-unix"
	ln -s "$wine/bin/winebuild" "$prefix/bin/winebuild"
	for l in libwinecrt0.a libntdll.a libdbghelp.a; do
		ln -s "$wine/lib/wine/$winearch-windows/$l" "$prefix/lib/wine/$winearch-windows/$l"
	done
	for l in ntdll.so winemac.so; do ln -s "$unixlibs/$l" "$prefix/lib/wine/$unixarch-unix/$l"; done

	cpu_family="$winearch"
	[[ $winearch == i386 ]] && cpu_family=x86
	cross="$OUT/cross-$arch.txt"
	cat > "$cross" <<-EOF
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
	cpu_family = '$cpu_family'
	cpu = '$winearch'
	endian = 'little'
	EOF
	opts=()
	while IFS= read -r o; do [[ -n $o ]] && opts+=("$o"); done < <(mf get "$id" dxmt.meson_options)
	bdir="$OUT/build-$arch"
	log="$LOGS/$id-dxmt-$arch.log"
	echo "==> DXMT $arch $(git -C "$SRC" describe --always), log $log"
	rm -rf "$bdir" "$OUT/stage-$arch"
	{
		meson setup --cross-file "$cross" -Dnative_llvm_path="$llvm" -Dwine_install_path="$prefix" \
			--buildtype release -Dstrip=true ${opts[@]+"${opts[@]}"} --prefix "$OUT/stage-$arch" "$bdir" "$SRC" &&
			meson compile -C "$bdir" && meson install -C "$bdir"
	} > "$log" 2>&1 || { tail -30 "$log"; exit 1; }
	dst="$OUT/install"
	rm -rf "$dst/$winearch-windows"
	mkdir -p "$dst/$winearch-windows"
	for d in d3d11 dxgi d3d10core winemetal; do cp "$OUT/stage-$arch/$winearch-windows/$d.dll" "$dst/$winearch-windows/"; done
	file "$dst/$winearch-windows/d3d11.dll" | sed "s|$OUT/||"
	# an i386 build's unix side is the x86_64 one: the x86_64 build installs it
	if [[ $arch != i386 ]]; then
		rm -rf "$dst/$unixarch-unix"
		mkdir -p "$dst/$unixarch-unix"
		cp "$OUT/stage-$arch/$unixarch-unix/winemetal.so" "$dst/$unixarch-unix/"
		file "$dst/$unixarch-unix/winemetal.so" | sed "s|$OUT/||"
	fi
done
