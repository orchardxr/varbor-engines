#!/usr/bin/env bash
# Check out an entry's DXMT and DXVK sources with our patches: build/<id>/src/{dxmt,dxvk}.
#   scripts/fetch-sources.sh <id> [dxmt] [dxvk]
# Each is a worktree of the upstream clone in build/src at the manifest commit, every patch committed on top, and an
# annotated tag <base>-varbor.<revision> at the result, so the vcs_tag (git describe) the DLLs log is ours, e.g.
# "v0.80-247-gfb451568-varbor.1" next to stock CrossOver's "v0.80-279-g8f06be3".
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
id="${1:?usage: $0 <id> [dxmt] [dxvk]}"
shift
libs=("$@")
[[ ${#libs[@]} -gt 0 ]] || libs=(dxmt dxvk)

export GIT_AUTHOR_NAME=VarboR GIT_AUTHOR_EMAIL=varbor@users.noreply.github.com
export GIT_COMMITTER_NAME=VarboR GIT_COMMITTER_EMAIL=varbor@users.noreply.github.com
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

for lib in "${libs[@]}"; do
	repo="$(mf get "$id" "$lib.repo")"
	commit="$(mf get "$id" "$lib.commit")"
	[[ -n $repo && -n $commit ]] || die "$id has no $lib source"
	up="$BUILD/src/$lib"
	[[ -d "$up/.git" ]] || git clone -q --no-checkout "$repo" "$up"
	git -C "$up" cat-file -e "$commit^{commit}" 2>/dev/null || git -C "$up" fetch -q origin "$commit"
	wt="$BUILD/$id/src/$lib"
	if [[ -e $wt ]]; then
		git -C "$up" worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
	fi
	git -C "$up" worktree prune
	mkdir -p "$(dirname "$wt")"
	git -C "$up" worktree add -q --detach "$wt" "$commit"
	while IFS= read -r s; do
		[[ -n $s ]] && git -C "$wt" submodule update -q --init "$s"
	done < <(mf get "$id" "$lib.submodules")
	while IFS= read -r p; do
		[[ -n $p ]] || continue
		git -C "$wt" apply --index --whitespace=nowarn "$ROOT/$p" || die "$p does not apply to $lib $commit"
		git -C "$wt" commit -q -m "$(sed -n 's/^Subject: \(\[PATCH\] \)\{0,1\}//p' "$ROOT/$p" | head -1)" -m "$p"
	done < <(mf get "$id" "$lib.patches")
	tag="$(engine_version_tag "$id" "$lib")"
	git -C "$wt" tag -f -a -m "$tag" "$tag" >/dev/null
	echo "$lib: $wt at $(git -C "$wt" describe --always) ($commit + $(mf get "$id" "$lib.patches" | grep -c .) patches)"
done
