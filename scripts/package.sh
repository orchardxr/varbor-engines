#!/usr/bin/env bash
# Package an entry's built engines as release assets in dist/:
#   varbor-engines-<tag>.tar.gz       dxmt/<arch>-{windows,unix}/*, dxvk/aarch64-windows/* (entries with a DXVK
#                                     build), licenses/, metadata.json
#   varbor-engines-<tag>-src.tar.gz   the patched DXMT/DXVK sources the binaries were built from (DXMT is LGPL)
#   metadata.json                     the same metadata, for VarboR to read without the tarball
#   SHA256SUMS
#   scripts/package.sh <id>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
id="${1:?usage: $0 <id>}"
tag="$(mf tag "$id")"
name="varbor-engines-$tag"
stage="$BUILD/$id/package/$name"
rm -rf "$BUILD/$id/package"
mkdir -p "$stage/licenses" "$DIST"
libs=()
for lib in dxmt dxvk; do [[ -n "$(mf get "$id" "$lib.repo")" ]] && libs+=("$lib"); done

for lib in "${libs[@]}"; do
	inst="$BUILD/$id/$lib/install"
	[[ -d $inst ]] || die "no $inst (scripts/build-$lib.sh $id)"
	mkdir -p "$stage/$lib"
	cp -R "$inst/" "$stage/$lib/"
	src="$BUILD/$id/src/$lib"
	for f in LICENSE LICENSE.OLD COPYING.LIB; do
		if [[ -f "$src/$f" ]]; then cp "$src/$f" "$stage/licenses/$(echo "$lib" | tr a-z A-Z)-$f"; fi
	done
done
cp "$ROOT/licenses/"* "$stage/licenses/"

# Sources: each worktree as git archive (DXMT with its directx headers submodule), plus our patches and manifest
srcstage="$BUILD/$id/package/$name-src"
mkdir -p "$srcstage"
for lib in "${libs[@]}"; do
	src="$BUILD/$id/src/$lib"
	git -C "$src" archive --prefix="$lib/" HEAD | tar -x -C "$srcstage"
	git -C "$src" submodule foreach --quiet 'echo $sm_path' | while IFS= read -r sm; do
		git -C "$src/$sm" archive --prefix="$lib/$sm/" HEAD | tar -x -C "$srcstage"
	done
done
cp -R "$ROOT/patches" "$ROOT/builds.json" "$ROOT/README.md" "$srcstage/"

wine_unix="stub"
[[ -n ${CX_RUNNER:-} ]] && wine_unix="runner"
python3 -I - "$ROOT/builds.json" "$id" "$tag" "$stage" "$ROOT" "$wine_unix" \
	"$(git -C "$BUILD/$id/src/dxmt" describe --always)" \
	"$([[ -d "$BUILD/$id/src/dxvk" && -n "$(mf get "$id" dxvk.repo)" ]] && git -C "$BUILD/$id/src/dxvk" describe --always)" \
	"$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)" "${LLVM_MINGW_VERSION}" <<-'EOF'
	import hashlib, json, os, sys, datetime
	manifest, ident, tag, stage, root, wine_unix, dxmt_v, dxvk_v, commit, mingw = sys.argv[1:]
	m = json.load(open(manifest))
	b = next(x for x in m["builds"] if x["id"] == ident)
	def sha(p):
	    return hashlib.sha256(open(p, "rb").read()).hexdigest()
	def files(lib):
	    out = {}
	    for d, _, fs in os.walk(os.path.join(stage, lib)):
	        for f in sorted(fs):
	            p = os.path.join(d, f)
	            out[os.path.relpath(p, stage)] = sha(p)
	    return dict(sorted(out.items()))
	def lib(name, version):
	    e = b[name]
	    return {
	        "version": version,
	        "stock_version": e["stock"]["version"],
	        "repo": e["repo"],
	        "commit": e["commit"],
	        "describe": e["describe"],
	        "patches": [{"file": p, "sha256": sha(os.path.join(root, p))} for p in e["patches"]],
	        "files": files(name),
	    }
	meta = {
	    "schema": 1,
	    "id": ident,
	    "tag": tag,
	    "revision": b["revision"],
	    "crossover": {k: b["crossover"][k] for k in ("version", "public_version", "wine", "unix_arches")},
	    "dxmt": lib("dxmt", dxmt_v),
	    "build": {
	        "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
	        "varbor_engines_commit": commit,
	        "llvm_mingw": mingw,
	        "llvm": b["dxmt"]["toolchain"]["llvm"],
	        "wine_unix_libs": wine_unix,
	    },
	    "licenses": {
	        "dxmt": "LGPL-2.1-or-later (licenses/DXMT-LICENSE, DXMT-COPYING.LIB)"
	        if os.path.exists(os.path.join(stage, "licenses", "DXMT-COPYING.LIB"))
	        else "MIT (licenses/DXMT-LICENSE)",
	        "dxvk": "Zlib (licenses/DXVK-LICENSE); CrossOver changes by CodeWeavers, Inc.",
	        "llvm": "Apache-2.0 WITH LLVM-exception (licenses/LLVM-LICENSE.TXT), statically linked into winemetal.so",
	    },
	    "source": f"varbor-engines-{tag}-src.tar.gz",
	}
	if b["dxvk"].get("repo"):
	    meta["dxvk"] = lib("dxvk", dxvk_v)
	else:
	    meta["dxvk"] = {"stock_version": b["dxvk"]["stock"]["version"], "note": b["dxvk"].get("note", "not built: stock")}
	    del meta["licenses"]["dxvk"]
	json.dump(meta, open(os.path.join(stage, "metadata.json"), "w"), indent=2)
	EOF

cp "$stage/metadata.json" "$DIST/metadata.json"
COPYFILE_DISABLE=1 tar -C "$(dirname "$stage")" -czf "$DIST/$name.tar.gz" "$name"
COPYFILE_DISABLE=1 tar -C "$(dirname "$srcstage")" -czf "$DIST/$name-src.tar.gz" "$name-src"
(cd "$DIST" && shasum -a 256 "$name.tar.gz" "$name-src.tar.gz" metadata.json > SHA256SUMS)
ls -l "$DIST"
cat "$DIST/SHA256SUMS"
