#!/usr/bin/env bash
# Print the CrossOver build and the DXMT/DXVK engine versions of runners, and the builds.json entry that matches.
#   scripts/detect-runner.sh [--json] RUNNER...
# RUNNER is a CrossOver root (holding lib/ and bin/), or a dir with CrossOver/ in it (a NotProton runner, or
# "CrossOver.app/Contents/SharedSupport"). With no RUNNER, every runner in NotProton's runners dir.
# Only reads the runner. Needs strings(1) and python3.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

json=0
[[ ${1:-} == --json ]] && { json=1; shift; }
runners=("$@")
if [[ ${#runners[@]} == 0 ]]; then
	for d in "$HOME/Library/Application Support/notproton/runners"/*/; do runners+=("${d%/}"); done
fi

dxmt_re="$(mf top detect.dxmt_regex)"
dxvk_re="$(mf top detect.dxvk_regex)"
ver_re="$(mf top detect.version_regex)"
wine_re="$(mf top detect.wine_regex)"

engine_versions() {
	local cx="$1" lib="$2" re="$3" d v
	for d in "$cx/lib/$lib"/*-windows; do
		[[ -f "$d/d3d11.dll" ]] || continue
		v="$(strings -a "$d/d3d11.dll" | grep -E "$re" | sort -u | paste -sd, -)"
		printf '%s\t%s\n' "$(basename "$d")" "${v:-unknown}"
	done
}

detect_one() {
	local r="$1" cx vf cxv pub date wine arch
	if [[ -d "$r/CrossOver/lib" ]]; then cx="$r/CrossOver"; else cx="$r"; fi
	[[ -d "$cx/lib/wine" ]] || { echo "$r: not a CrossOver runner" >&2; return 1; }
	vf="$cx/lib/python/distversion.pyc"
	[[ -f $vf ]] || vf="$cx/lib/python/distversion.py"
	cxv="" pub="" date=""
	if [[ -f $vf ]]; then
		# The marshalled strings after CX_VERSION: version, public version (names the sources tarball), date
		{ read -r cxv; read -r pub; read -r date; } < <(strings -a "$vf" | head -3 | sed -E 's/^[zZ]//; s/[zZ]$//') || true
		cxv="$(printf '%s\n' "$cxv" | grep -oE "$ver_re" | head -1 || true)"
	fi
	wine=""
	for arch in aarch64 x86_64; do
		[[ -f "$cx/lib/wine/$arch-unix/ntdll.so" ]] || continue
		wine="$(strings -a "$cx/lib/wine/$arch-unix/ntdll.so" | grep -oE "$wine_re" | head -1 || true)"
		break
	done
	local unix_arches
	unix_arches="$(cd "$cx/lib/wine" && ls -d *-unix 2>/dev/null | sed 's/-unix$//' | paste -sd, -)"
	local entry="" status="unknown" note=""
	if [[ -n $cxv ]] && entry="$(mf match "$cxv")"; then
		if [[ "$(mf get "$entry" build)" == true ]]; then status="supported"; else status="known, not built"; fi
	else
		entry=""
	fi
	local dxmt dxvk
	dxmt="$(engine_versions "$cx" dxmt "$dxmt_re")"
	dxvk="$(engine_versions "$cx" dxvk "$dxvk_re")"
	if [[ -n $entry ]]; then
		local want_dxmt want_dxvk
		want_dxmt="$(mf get "$entry" dxmt.stock.version)"
		want_dxvk="$(mf get "$entry" dxvk.stock.version)"
		local lib got want
		for lib in DXMT DXVK; do
			if [[ $lib == DXMT ]]; then got="$dxmt" want="$want_dxmt"; else got="$dxvk" want="$want_dxvk"; fi
			# a clone with our engines (VarboR's own, -varbor.<revision>) next to stock arches is expected, not foreign
			if printf '%s\n' "$got" | cut -f2 | grep -qE -- '-varbor\.[0-9]+$'; then
				note+="$lib from varbor-engines ($(printf '%s\n' "$got" | cut -f2 | grep -E -- '-varbor\.[0-9]+$' | sort -u | paste -sd, -)); "
			elif printf '%s\n' "$got" | cut -f2 | grep -qv -x -F "$want"; then
				note+="$lib differs from stock $want; "
			fi
		done
		note="${note%; }"
	fi
	if [[ $json == 1 ]]; then
		python3 -I -c 'import json,sys
a=sys.argv
def eng(s): return {l.split("\t")[0]: l.split("\t")[1] for l in s.splitlines() if l}
print(json.dumps({"runner": a[1], "crossover": {"version": a[2], "public_version": a[3], "date": a[4], "wine": a[5], "unix_arches": [x for x in a[6].split(",") if x]}, "dxmt": eng(a[7]), "dxvk": eng(a[8]), "entry": a[9] or None, "status": a[10], "note": a[11] or None}))' \
			"$r" "$cxv" "$pub" "$date" "$wine" "$unix_arches" "$dxmt" "$dxvk" "$entry" "$status" "$note"
	else
		echo "runner:     $r"
		echo "crossover:  ${cxv:-unknown} (public ${pub:-?}, ${date:-?})"
		echo "wine:       ${wine:-unknown} [${unix_arches}]"
		printf '%s\n' "$dxmt" | while IFS=$'\t' read -r a v; do [[ -n $a ]] && printf 'dxmt:       %-16s %s\n' "$a" "$v"; done
		printf '%s\n' "$dxvk" | while IFS=$'\t' read -r a v; do [[ -n $a ]] && printf 'dxvk:       %-16s %s\n' "$a" "$v"; done
		echo "entry:      ${entry:-none} ($status)${entry:+, release $(mf tag "$entry")}"
		[[ -z $note ]] || echo "note:       $note"
		echo
	fi
}

rc=0
for r in "${runners[@]}"; do detect_one "$r" || rc=1; done
exit $rc
