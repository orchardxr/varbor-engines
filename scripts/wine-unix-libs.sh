#!/usr/bin/env bash
# The ntdll.so/winemac.so winemetal.so links against, for one entry and unix arch; prints their directory.
#   scripts/wine-unix-libs.sh <id> <aarch64|x86_64>
# With CX_RUNNER (a CrossOver root, or a dir holding CrossOver/) the runner's own lib/wine/<arch>-unix files are used.
# Without it (CI: CrossOver can't be downloaded there) stub dylibs are built that export exactly the symbols the
# manifest's dxmt.wine_unix.links lists, with the install names @rpath/ntdll.so and @rpath/winemac.so, so
# winemetal.so's load commands and bindings come out the same as when linked against the runner. If DXMT starts
# importing another symbol the link fails and the manifest needs it.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
id="${1:?usage: $0 <id> <aarch64|x86_64>}"
arch="${2:?usage: $0 <id> <aarch64|x86_64>}"
out="$BUILD/$id/wine-unix-$arch"
mkdir -p "$out"

if [[ -n ${CX_RUNNER:-} ]]; then
	cx="$CX_RUNNER"
	[[ -d "$cx/CrossOver/lib" ]] && cx="$cx/CrossOver"
	for l in ntdll.so winemac.so; do
		[[ -f "$cx/lib/wine/$arch-unix/$l" ]] || die "no $cx/lib/wine/$arch-unix/$l"
		ln -sf "$cx/lib/wine/$arch-unix/$l" "$out/$l"
	done
	echo "$out"
	exit 0
fi

clang_arch="$arch"
[[ $arch == aarch64 ]] && clang_arch=arm64
links="$(mf get "$id" dxmt.wine_unix.links)"
for l in ntdll.so winemac.so; do
	src="$out/${l%.so}-stub.c"
	: > "$src"
	for s in $(python3 -I -c 'import json,sys; print(" ".join(json.loads(sys.argv[1]).get(sys.argv[2], [])))' "$links" "$l"); do
		echo "void ${s#_}(void) {}" >> "$src"
	done
	rm -f "$out/$l"
	clang -arch "$clang_arch" -mmacosx-version-min=10.15 -dynamiclib -install_name "@rpath/$l" -o "$out/$l" "$src"
done
echo "$out"
