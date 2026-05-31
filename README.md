openssl:provider-abi WIT
========================

WIT mirror of the OpenSSL 3 provider ABI (`OSSL_PROVIDER`,
`OSSL_DISPATCH`, `OSSL_ALGORITHM`, `OSSL_PARAM`, and the
`OSSL_FUNC_*` families from `<openssl/core_dispatch.h>`).

Lets OpenSSL 3 providers ship as wasm components instead of
`.so`/`.dll` files. openssl-wasm imports this world; provider
components export it.

Status: **Phase 1b + Phase 8 STORE complete** — Layer-1 surface is
sufficient for TLS 1.2 / 1.3 server-side, client-cert auth, and
`SSLContext.load_cert_chain('pkcs11:...')` via the STORE op
end-to-end through a real HSM. See [ARCHITECTURE.md](ARCHITECTURE.md)
for the full layered stack + composition recipes.

- `pkey/pkey.wit` — shared types: `OSSL_PARAM` variant, key-selection
  flags, `pkey-error` (with `insufficient-buffer(u64)`), `operation`
  enum (replaces raw `s32` for OSSL_OP_*), four resource handles
  (`keydata`, `gen-context`, `signature-context`, `asym-cipher-context`).
- `keymgmt/keymgmt.wit` — all 25 OSSL_FUNC_KEYMGMT_* mapped.
- `signature/signature.wit` — OSSL_FUNC_SIGNATURE_* IDs 1–26. The
  3.2+ one-shot sign-message family (27–32) is deferred to Phase 8.
- `asym-cipher/asym-cipher.wit` — all 11 OSSL_FUNC_ASYM_CIPHER_* mapped.
- `provider/provider.wit` — OSSL_FUNC_PROVIDER_* IDs 1024–1032 (the
  "provider-implements" side). Reverse-direction "core-provided" funcs
  (IDs 105–120+) are not in this WIT — they live on the openssl-wasm
  side as Phase 2 callback-direction work.
- `worlds/provider-abi.wit` exports all five interfaces.

Generated surface: 812 lines of C; 36 keymgmt + 34 signature + 19
asym-cipher + 23 provider + 8 pkey exported funcs.

Phase 2 (`openssl-wasm` loader patch) is the next milestone.

See `~/git/python-wasm/plans/openssl-provider-wit.md` for the
architecture and 13-phase implementation plan, and
`docs/architecture.md` for the standalone version of the design.

Layout
------

```
pkey/pkey.wit                 shared types: OSSL_PARAM variant, key-selection
                              flags, pkey-error variant, operation enum,
                              opaque resource handles
provider/provider.wit         OSSL_PROVIDER entry point (Phase 1b)
keymgmt/keymgmt.wit           OSSL_OP_KEYMGMT (Phase 1a, 25 funcs)
signature/signature.wit       OSSL_OP_SIGNATURE (Phase 1a, IDs 1-26)
asym-cipher/asym-cipher.wit   OSSL_OP_ASYM_CIPHER (Phase 1b, 11 funcs)
worlds/provider-abi.wit       the Layer-1 contract (combines all)
docs/architecture.md          design overview
scripts/check-wit.sh          resolve + wit-bindgen c + wasi-sdk clang compile
```

How a C provider author reads this
----------------------------------

Each interface (`keymgmt`, `signature`, ...) has top-of-file comments
mapping every `OSSL_FUNC_*` ID to the WIT method that replaces it.
Two intentional model shifts:

- C `void *provctx` / `keydata` / `genctx` / `sigctx` become typed
  WIT resources. Their `*_free` / `*_cleanup` C functions collapse
  into the WIT resource destructor (guaranteed to run on drop).
- C `int 0=fail / 1=ok` returns become `result<_, pkey-error>` /
  `result<T, pkey-error>`. Output-buffer parameters (`siglen`,
  `routlen`) become `result<list<u8>, pkey-error>`; insufficient-
  buffer surfaces via `pkey-error::insufficient-buffer(u64)` so
  callers can probe the required size and retry.

Backfill (Phase 8) adds sibling interfaces for key-exchange, kdf, mac,
digest, cipher, kem, rand, encoder, decoder, store.

Pinned OpenSSL version
----------------------

The WIT surface tracks **OpenSSL 3.6.2** (release date 2026-04-07, as
shipped in `~/git/openssl-wasm/third_party/openssl/`).

`core_dispatch.h` SHA-1 we're modeling against:
**`c475666c52be37e02f0236cbe80ae3faaf54ed8b`** (from openssl-wasm's
vendored tree).

When OpenSSL 3.x adds new `OSSL_FUNC_*` IDs, bump the package version
of the affected interface (semver-minor for additions, semver-major
for any signature change). Mismatched provider/host versions surface
at link time, not at runtime.

Related repos (the full openssl-wasm component stack)
-----------------------------------------------------

| Layer | Repo | Role |
|---|---|---|
| Layer 1 (spec) | [openssl-provider-wit](https://github.com/tegmentum/openssl-provider-wit) | This repo — WIT mirror of the OpenSSL 3 provider ABI |
| Layer 0 (consumer) | [openssl-wasm](https://github.com/tegmentum/openssl-wasm) | OpenSSL 3 compiled to wasm; imports this WIT; bridges OSSL_OP_* to WIT calls |
| Layer 2 (OSSL adapter) | [simple-provider-adapter](https://github.com/tegmentum/simple-provider-adapter) | Exports openssl:provider-abi, imports narrow tegmentum:key-backend |
| Layer 2 (STORE backend) | [pkcs11-store-adapter](https://github.com/tegmentum/pkcs11-store-adapter) | Exports openssl:store/store, imports pkcs11:host. Resolves pkcs11: URIs to cert DER + key-references. |
| Layer 3 (key backend) | [pkcs11-bridge](https://github.com/tegmentum/pkcs11-bridge) | Exports tegmentum:key-backend, imports pkcs11:host |
| Layer 4 (browser) | [pkcs11-gateway-adapter](https://github.com/tegmentum/pkcs11-gateway-adapter) | Exports pkcs11:host via tegmentum:pkcs11-tunnel (WebSocket) |
| Bridge (Node) | [ws-gateway-server](https://github.com/tegmentum/ws-gateway-server) | Reference Node server for the KSW1 WebSocket tunnel |

See [ARCHITECTURE.md](ARCHITECTURE.md) for composition recipes.
