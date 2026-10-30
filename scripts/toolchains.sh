#!/usr/bin/env bash
# Fetch or build the toolchains an entry needs into build/toolchains, and print them as shell assignments.
#   scripts/toolchains.sh <id> [llvm-mingw] [llvm-arm64] [llvm-x86_64] [wine-arm64ec] [wine-x86_64]   (default: all)
# Each is taken from the environment when set:
#   LLVM_MINGW      llvm-mingw (ucrt, macOS universal), default release $LLVM_MINGW_VERSION
#   LLVM15_ARM64    LLVM 15 with headers and static libs for arm64 macOS (DXMT's airconv, linked into winemetal.so)
#   LLVM15_X86_64   the same for x86_64 macOS; both built from source when unset (~30 min each, cached in CI)
#   WINE_ARM64EC    a Wine install with lib/wine/aarch64-windows import libs and bin/winebuild (DXMT CI's wine-11.2)
#   WINE_X86_64     the same for x86_64 (DXMT CI's v8.16-3shain)
# None of these is CrossOver's Wine: the PE side only needs Wine's import libs and winebuild; winemetal.so's link
# against CrossOver's ntdll.so/winemac.so is scripts/wine-unix-libs.sh.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

id="${1:?usage: $0 <id> [toolchain...]}"
shift
want=("$@")
[[ ${#want[@]} -gt 0 ]] || want=(llvm-mingw llvm-arm64 llvm-x86_64 wine-arm64ec wine-x86_64)

llvm_mingw() {
	if [[ -n ${LLVM_MINGW:-} ]]; then echo "$LLVM_MINGW"; return; fi
	local dir="$TC/$LLVM_MINGW_NAME"
	if [[ ! -x "$dir/bin/arm64ec-w64-mingw32-clang" ]]; then
		curl -fsSL "https://github.com/mstorsjo/llvm-mingw/releases/download/$LLVM_MINGW_VERSION/$LLVM_MINGW_NAME.tar.xz" \
			| tar -xJ -C "$TC"
	fi
	echo "$dir"
}

llvm15() {
	local arch="$1" var="$2" ref dir
	if [[ -n ${!var:-} ]]; then echo "${!var}"; return; fi
	ref="$(mf get "$id" dxmt.toolchain.llvm)"
	dir="$TC/llvm-15-$arch"
	if [[ ! -f "$dir/lib/libLLVMCore.a" ]]; then
		[[ -d "$TC/llvm-project" ]] || git clone -q --depth 1 --branch "$ref" https://github.com/llvm/llvm-project.git "$TC/llvm-project"
		echo "==> LLVM $ref ($arch), log $LOGS/llvm-$arch.log" >&2
		{
			cmake -B "$TC/llvm-build-$arch" -S "$TC/llvm-project/llvm" -G Ninja \
				-DCMAKE_INSTALL_PREFIX="$dir" -DCMAKE_OSX_ARCHITECTURES="$arch" -DLLVM_HOST_TRIPLE="$arch-apple-darwin" \
				-DLLVM_ENABLE_ASSERTIONS=On -DLLVM_ENABLE_ZSTD=Off -DCMAKE_BUILD_TYPE=Release -DLLVM_TARGETS_TO_BUILD="" \
				-DLLVM_BUILD_TOOLS=Off -DLLVM_INCLUDE_BENCHMARKS=Off -DCMAKE_CXX_FLAGS="-D_LIBCPP_KEEP_TRANSITIVE_INCLUDES_LLVM23" \
				-DLLVM_VERSION_PRINTER_SHOW_HOST_TARGET_INFO=Off
			cmake --build "$TC/llvm-build-$arch"
			cmake --install "$TC/llvm-build-$arch"
		} > "$LOGS/llvm-$arch.log" 2>&1 || { tail -30 "$LOGS/llvm-$arch.log" >&2; exit 1; }
		rm -rf "$TC/llvm-build-$arch"
	fi
	echo "$dir"
}

wine_tc() {
	local var="$1" key="$2" strip="$3" url dir
	if [[ -n ${!var:-} ]]; then echo "${!var}"; return; fi
	url="$(mf get "$id" "dxmt.toolchain.$key")"
	dir="$TC/$key-$(basename "$(dirname "$url")")"
	if [[ ! -x "$dir/bin/winebuild" ]]; then
		mkdir -p "$dir"
		curl -fsSL "$url" | tar -xz --strip-components "$strip" -C "$dir"
	fi
	echo "$dir"
}

for t in "${want[@]}"; do
	case "$t" in
	llvm-mingw) echo "LLVM_MINGW='$(llvm_mingw)'" ;;
	llvm-arm64) echo "LLVM15_ARM64='$(llvm15 arm64 LLVM15_ARM64)'" ;;
	llvm-x86_64) echo "LLVM15_X86_64='$(llvm15 x86_64 LLVM15_X86_64)'" ;;
	# wine-11.2.tar.gz unpacks as ./wine-11.2/<prefix>, wine.tar.gz as ./<prefix>
	wine-arm64ec) echo "WINE_ARM64EC='$(wine_tc WINE_ARM64EC wine_arm64ec 2)'" ;;
	wine-x86_64) echo "WINE_X86_64='$(wine_tc WINE_X86_64 wine_x86_64 1)'" ;;
	*) die "unknown toolchain $t" ;;
	esac
done
