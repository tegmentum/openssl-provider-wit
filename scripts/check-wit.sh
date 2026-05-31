#!/usr/bin/env bash
# Confirm the WIT packages resolve, generate clean C bindings, and
# compile cleanly under wasi-sdk clang.
#
# Stages a temporary `wit/` + `wit/deps/` tree because wit-bindgen
# wants a single wit root with cross-package deps as siblings (it
# can't follow this repo's per-interface directories directly).
#
# Requirements:
#   wit-bindgen (`cargo install wit-bindgen-cli`)
#   Optional:   wasi-sdk clang on PATH or pointed at by WASI_SDK_CLANG.
#               If absent, the compile step is skipped with a warning.

set -euo pipefail
cd "$(dirname "$0")/.."

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

for iface in pkey provider keymgmt signature asym-cipher store encoder decoder; do
  mkdir -p "$STAGE/wit/deps/$iface"
  cp "$iface/$iface.wit" "$STAGE/wit/deps/$iface/"
done
cp worlds/provider-abi.wit "$STAGE/wit/world.wit"

wit-bindgen c --world provider-abi --out-dir "$STAGE/out" "$STAGE/wit"
echo "OK: openssl:provider-abi@0.1.0 resolves; bindings generated to $STAGE/out"

# Phase 1a "Done when" gate: bindings must compile under the actual
# wasm32-wasip2 toolchain. Host cc trips on the wasm-specific
# __export_name__ attribute, so we need a real wasi-sdk clang.
CLANG="${WASI_SDK_CLANG:-}"
if [ -z "$CLANG" ]; then
  for candidate in \
      "$HOME/git/python-wasm/deps/wasi-sdk-33.0-arm64-macos/bin/clang" \
      "$HOME/git/openssl-wasm/.wasi-sdk/bin/clang" \
      wasm32-wasi-clang; do
    if command -v "$candidate" >/dev/null 2>&1; then
      CLANG="$candidate"
      break
    fi
  done
fi

if [ -n "$CLANG" ] && command -v "$CLANG" >/dev/null 2>&1; then
  "$CLANG" --target=wasm32-wasip2 -Wall -Wextra -Werror \
    -c "$STAGE/out/provider_abi.c" \
    -o "$STAGE/out/provider_abi.o"
  echo "OK: provider_abi.c compiles cleanly under $CLANG --target=wasm32-wasip2"
else
  echo "WARN: no wasi-sdk clang found; skipping wasm compile check." >&2
  echo "      Install wasi-sdk or set WASI_SDK_CLANG to enable." >&2
fi
