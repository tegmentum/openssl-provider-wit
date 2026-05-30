#!/usr/bin/env bash
# Phase 0 sanity check: confirm the WIT packages resolve and generate
# bindings cleanly. Stages a temporary `wit/` + `wit/deps/` tree because
# wit-bindgen wants a single wit root with cross-package deps as
# siblings (it can't follow this repo's per-interface directories
# directly).
#
# Requirements: wit-bindgen (`cargo install wit-bindgen-cli`).

set -euo pipefail
cd "$(dirname "$0")/.."

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

for iface in provider keymgmt signature asym-cipher; do
  mkdir -p "$STAGE/wit/deps/$iface"
  cp "$iface/$iface.wit" "$STAGE/wit/deps/$iface/"
done
cp worlds/provider-abi.wit "$STAGE/wit/world.wit"

wit-bindgen c --world provider-abi --out-dir "$STAGE/out" "$STAGE/wit"
echo "OK: openssl:provider-abi@0.1.0 resolves; bindings generated to $STAGE/out"
