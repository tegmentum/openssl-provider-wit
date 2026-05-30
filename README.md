openssl:provider-abi WIT
========================

WIT mirror of the OpenSSL 3 provider ABI (`OSSL_PROVIDER`,
`OSSL_DISPATCH`, `OSSL_ALGORITHM`, `OSSL_PARAM`, and the
`OSSL_FUNC_*` families from `<openssl/core_dispatch.h>`).

Lets OpenSSL 3 providers ship as wasm components instead of
`.so`/`.dll` files. openssl-wasm imports this world; provider
components export it.

Status: **Phase 1a** (keymgmt + signature + shared types).
`pkey/pkey.wit` ships the shared `OSSL_PARAM` model, `key-selection`
flags, `pkey-error` variant, and the four resource handles
(`provider-context`, `keydata`, `gen-context`, `signature-context`,
`asym-cipher-context`). `keymgmt/keymgmt.wit` mirrors all 25 funcs of
`OSSL_OP_KEYMGMT` (function IDs documented inline). `signature/
signature.wit` mirrors the streaming OSSL_OP_SIGNATURE surface (the
3.2+ one-shot sign-message family is deferred to Phase 8). Phase 1b
adds `provider/provider.wit` entry point + `asym-cipher/asym-cipher.wit`.

See `~/git/python-wasm/plans/openssl-provider-wit.md` for the
architecture and 13-phase implementation plan, and
`docs/architecture.md` for the standalone version of the design.

Layout
------

```
pkey/pkey.wit                 shared types: OSSL_PARAM variant, key-selection
                              flags, pkey-error variant, opaque resources
provider/provider.wit         OSSL_PROVIDER entry point (Phase 1b placeholder)
keymgmt/keymgmt.wit           OSSL_OP_KEYMGMT (~25 funcs, Phase 1a)
signature/signature.wit       OSSL_OP_SIGNATURE (~20 funcs, Phase 1a)
asym-cipher/asym-cipher.wit   OSSL_OP_ASYM_CIPHER (Phase 1b placeholder)
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

Related repos
-------------

- `tegmentum:key-backend-wit`   Layer-3 narrow contract for typical backends
- `pkcs11-wit`                  Layer-4 PKCS#11 (existing)
- `pkcs11-wasm-host`            Layer-4 native pkcs11 on wasmtime (existing)
- `openssl-wasm`                Layer-0 consumer; patched in Phase 2
