# openssl-wasm Component Stack — Architecture

This document is the entry point for understanding how the seven repos in the openssl-wasm component stack fit together, and the canonical recipes for composing them into a working TLS / HSM-backed app.

## The four layers

```
┌────────────────────────────────────────────────────────────────────────┐
│  Layer 0:  openssl-wasm                                                │
│            OpenSSL 3 + libssl + libcrypto compiled to wasm32-wasip2    │
│            Exports user-facing API (TLS, X509, EVP_PKEY, ...)          │
│            Imports openssl:provider-abi + openssl:store/store          │
└─────────────────────────────────────┬──────────────────────────────────┘
                                      │  openssl:provider-abi
                                      │  openssl:store/store
                                      ▼
┌────────────────────────────────────────────────────────────────────────┐
│  Layer 1:  openssl-provider-wit  (this repo — WIT spec only)           │
│            WIT mirror of OSSL_DISPATCH / OSSL_PARAM / OSSL_ALGORITHM   │
│            5 interfaces (pkey, keymgmt, signature, asym-cipher,        │
│            provider) + Phase 8 store. No implementation.               │
└─────────────────────────────────────┬──────────────────────────────────┘
                                      │
                                      ▼
┌────────────────────────────────────────────────────────────────────────┐
│  Layer 2:  Provider adapters — implement openssl-provider-abi          │
│                                                                        │
│  simple-provider-adapter      pkcs11-store-adapter                     │
│  └ exports provider-abi       └ exports openssl:store/store            │
│  └ imports key-backend        └ imports pkcs11:host                    │
└─────────────────┬─────────────────────────────┬────────────────────────┘
                  │  tegmentum:key-backend      │  pkcs11:host
                  ▼                             ▼
┌────────────────────────────────────────────────────────────────────────┐
│  Layer 3:  Key backends — adapt domain APIs to key-backend             │
│                                                                        │
│  pkcs11-bridge                 (future: webauthn-bridge,               │
│  └ exports key-backend          webcrypto-bridge, software-bridge,     │
│  └ imports pkcs11:host          tpm-bridge, ...)                       │
└─────────────────┬──────────────────────────────────────────────────────┘
                  │  pkcs11:host
                  ▼
┌────────────────────────────────────────────────────────────────────────┐
│  Layer 4:  pkcs11:host providers — actual PKCS#11 surface              │
│                                                                        │
│  pkcs11-provider + softhsm     pkcs11-gateway-adapter                  │
│  (native / wasmtime)           (browser → ws-gateway → host pkcs11js)  │
│                                                                        │
│  pkcs11-webauthn-adapter       pkcs11-webcrypto-adapter                │
│  (subset — WebAuthn assertion) (broad — SubtleCrypto + IndexedDB)      │
└────────────────────────────────────────────────────────────────────────┘
```

## What each repo does

| Repo | Type | Role |
|---|---|---|
| **[openssl-provider-wit](https://github.com/tegmentum/openssl-provider-wit)** | WIT only | Layer-1 spec: WIT mirror of OpenSSL 3 provider ABI |
| **[openssl-wasm](https://github.com/tegmentum/openssl-wasm)** | C → wasm component | Layer-0 consumer: OpenSSL 3 + WIT bridge. Imports provider-abi + store. |
| **[simple-provider-adapter](https://github.com/tegmentum/simple-provider-adapter)** | Rust → wasm | Layer-2 OSSL provider adapter. Exports provider-abi, imports `tegmentum:key-backend`. |
| **[pkcs11-store-adapter](https://github.com/tegmentum/pkcs11-store-adapter)** | Rust → wasm | Layer-2 STORE backend. Exports `openssl:store/store`, imports `pkcs11:host`. |
| **[pkcs11-bridge](https://github.com/tegmentum/pkcs11-bridge)** | Rust → wasm | Layer-3 key backend. Exports `tegmentum:key-backend`, imports `pkcs11:host`. |
| **[pkcs11-gateway-adapter](https://github.com/tegmentum/pkcs11-gateway-adapter)** | Rust → wasm | Layer-4 browser-side. Exports `pkcs11:host` via WebSocket tunnel. |
| **[ws-gateway-server](https://github.com/tegmentum/ws-gateway-server)** | Node npm | Reference KSW1 WebSocket server — bridges browser tunnel to host pkcs11js. |
| **[pkcs11-webauthn-adapter](https://github.com/tegmentum/pkcs11-webauthn-adapter)** | Rust → wasm | Layer-4 alternative. Exports a `pkcs11:host` subset backed by `navigator.credentials.*`. |
| **[pkcs11-webcrypto-adapter](https://github.com/tegmentum/pkcs11-webcrypto-adapter)** | Rust → wasm | Layer-4 alternative. Exports a broader `pkcs11:host` subset backed by `crypto.subtle.*` + IndexedDB. |

## Composition recipes

The four canonical compositions, each a `wac compose` or `wac plug` chain. Pick the one matching your use case.

### Recipe 1 — Standalone TLS server (no HSM)

```
openssl-wasm + noop-provider  → composed.wasm
```

Just OpenSSL in wasm, no provider operations. Default `make build` flow. Use when you need OpenSSL primitives (X509 parsing, PEM encoding, TLS with PEM keys) but no provider backend.

### Recipe 2 — Standalone TLS server with HSM-backed key

```
openssl-wasm
  + simple-provider-adapter      (Layer 2 OSSL adapter)
  + pkcs11-bridge                (Layer 3 key backend)
  + pkcs11-store-adapter         (Layer 2 STORE backend, optional)
  + pkcs11-provider              (Layer 4 pkcs11:host export)
  + softhsm2.component           (the actual SoftHSM)
  → composed.wasm
```

All wasm, no Node bridge. The TLS handshake's `sign` and the cert chain load both reach a SoftHSM instance running inside the same composed wasm.

**Manifest:** uses `wac compose` not `wac plug` so `pkcs11-store-adapter` + `pkcs11-bridge` share ONE `pkcs11-provider` instance. See [python-wasm/scripts/wit-bridge-compose.wac](https://github.com/tegmentum/python-wasm/blob/main/scripts/wit-bridge-compose.wac).

**User code:**
```python
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_uri('pkcs11:object=tls-server;pin-value=1234')
with ctx.bind_tls('0.0.0.0', 8443) as srv:
    while True: srv.accept()
```

### Recipe 3 — Browser TLS with HSM key on a gateway machine

```
openssl-wasm
  + simple-provider-adapter
  + pkcs11-bridge
  + pkcs11-store-adapter
  + pkcs11-gateway-adapter       (Layer 4 — replaces pkcs11-provider for browser)
  → composed.wasm  → jco transpile → browser bundle

[gateway machine, standalone Node]
  npm install @tegmentum/ws-gateway-server pkcs11js
  PKCS11_BACKEND=pkcs11js PKCS11_LIB=/path/to/libpkcs11.so \
      npx ws-gateway-server
```

Browser-hosted wasm tunnels all PKCS#11 calls (KSW1 frames over WebSocket) to a gateway Node process which calls `pkcs11js` against a local libpkcs11. PINs and key material never leave the gateway machine.

**Manifest:** see [python-wasm/scripts/compose-python-component.sh](https://github.com/tegmentum/python-wasm/blob/main/scripts/compose-python-component.sh) `WITH_PKCS11_GATEWAY=1` flow.

### Recipe 4 — Browser TLS with a software key (no HSM)

```
openssl-wasm
  + simple-provider-adapter
  + (future: software-bridge OR pkcs11-bridge against a wasm-resident SoftHSM)
  → composed.wasm  → jco transpile → browser bundle
```

Useful for dev environments / demos where you don't want to operate an HSM. Either route through pkcs11-bridge against a wasm-resident SoftHSM (recipe 2 minus the gateway), or write a `software-bridge` Layer-3 implementation that stores key bytes in IndexedDB.

### Recipe 5 — Browser TLS with WebAuthn-registered credentials

```
openssl-wasm
  + simple-provider-adapter
  + pkcs11-bridge
  + pkcs11-store-adapter
  + pkcs11-webauthn-adapter      (Layer 4 — replaces pkcs11-provider+softhsm)
  → composed.wasm  → jco transpile → browser bundle
```

No gateway server needed; the polyfill's `webauthn-bridge` plugin calls `navigator.credentials.{create,get}` directly. Best fit: "user signs with their personal YubiKey / Touch ID / Windows Hello." Subset only — no `decrypt` / `derive-key` / multipart. Registration happens out of band (separate /register page) by default; opt in to `generate-key-pair`-triggers-WebAuthn-register via polyfill option.

**Manifest:** `WITH_PKCS11_WEBAUTHN=1 bash scripts/compose-python-component.sh`.

### Recipe 6 — Browser TLS with SubtleCrypto + IndexedDB keys

```
openssl-wasm
  + simple-provider-adapter
  + pkcs11-bridge
  + pkcs11-store-adapter
  + pkcs11-webcrypto-adapter     (Layer 4 — replaces pkcs11-provider+softhsm)
  → composed.wasm  → jco transpile → browser bundle
```

Broader coverage than recipe 5 because SubtleCrypto is a real key-management surface: sign / verify / encrypt / decrypt / generate-key / import-key. Keys live as non-extractable CryptoKey objects (default: IndexedDB-persistent; switchable to in-memory at compose time). Best fit: dev/test, ephemeral signing, software-protected keys without HSM dependency.

**Manifest:** `WITH_PKCS11_WEBCRYPTO=1 bash scripts/compose-python-component.sh`.

## Key design decisions

| Decision | Rationale |
|---|---|
| Layer 1 is WIT-only | Specs evolve independently of any implementation; multiple OpenSSL forks could implement against the same WIT |
| Layer 3 is a narrow `tegmentum:key-backend` | A new backend (WebAuthn, software, TPM, KMS) implements ~7 methods on a `key` resource — not 120 OSSL_FUNC_* dispatches |
| `pkcs11:host` is the line where PKCS#11 enters the picture | Lets us put softhsm, hardware HSMs, gateway tunnels, or even WebCrypto behind it uniformly |
| `store-object::key-reference(bytes)` not `keydata` | OSSL_OBJECT_PARAM_REFERENCE round-trips opaque bytes back to keymgmt.load; resource handles don't survive that |
| `wac compose` (not `wac plug`) for sharing instances | wac plug satisfies each importer independently; sharing pkcs11:host between pkcs11-bridge + pkcs11-store-adapter needs an explicit manifest |
| ws-gateway-server is its own npm package | Reusable from any browser-wasm project, not just python-wasm |

## Versioning policy

All Layer-1 interfaces and Layer-2/3/4 exports are versioned `@0.1.0` for the Phase 1–8 work. Bumps follow:

- **patch** — bug fixes, no surface change
- **minor** — backwards-compatible additions (new OSSL_FUNC_*, new optional fields)
- **major** — signature changes, removed methods

WIT version mismatch surfaces at link time (wac plug / wac compose fails), not at runtime. Composition outputs pin the exact dependency versions; bumping a Layer-1 WIT triggers a full re-compose of every dependent.

## How to add a new Layer-3 backend

1. Create new Rust crate `<your>-bridge`.
2. Add `wit/world.wit`: `export tegmentum:key-backend; import <your-domain-deps>`.
3. Implement `~7 methods` on the `key` resource (sign, verify, decrypt, derive, get_public, get_params, drop).
4. Build: `cargo build --target wasm32-wasip2 --release`.
5. Compose: wac compose `simple-provider-adapter + <your>-bridge + ...` into openssl-wasm.

That's it. The 120-func OSSL_DISPATCH surface is handled by simple-provider-adapter; you write your domain-specific bits only.

## See also

- [openssl-provider-wit/README.md](README.md) — Layer-1 spec details, WIT layout
- [python-wasm/plans/openssl-provider-wit.md](https://github.com/tegmentum/python-wasm/blob/main/plans/openssl-provider-wit.md) — the original 13-phase implementation plan (now mostly complete through Phase 8)
- Per-repo READMEs for layer-specific details
