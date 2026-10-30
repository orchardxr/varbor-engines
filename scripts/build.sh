#!/usr/bin/env bash
# Build and package one manifest entry: sources, DXMT, DXVK, release assets in dist/.
#   scripts/build.sh <id>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
id="${1:?usage: $0 <id>  (ids: $(mf ids --buildable | paste -sd' ' -))}"
[[ "$(mf get "$id" build)" == true ]] || die "$id is not buildable: $(mf get "$id" build_note)"
"$ROOT/scripts/fetch-sources.sh" "$id"
"$ROOT/scripts/build-dxmt.sh" "$id"
"$ROOT/scripts/build-dxvk.sh" "$id"
"$ROOT/scripts/package.sh" "$id"
