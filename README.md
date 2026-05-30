openssl:provider-abi WIT
========================

WIT mirror of the OpenSSL 3 provider ABI (`OSSL_PROVIDER`,
`OSSL_DISPATCH`, `OSSL_ALGORITHM`, `OSSL_PARAM`, and the
`OSSL_FUNC_*` families from `<openssl/core_dispatch.h>`).

Lets OpenSSL 3 providers ship as wasm components instead of
`.so`/`.dll` files. openssl-wasm imports this world; provider
components export it.

Status: **Phase 0** (skeleton). The four core operation interfaces
(provider entry, keymgmt, signature, asym-cipher) are present and
empty. The full surface lands in Phases 1a + 1b.

See `~/git/python-wasm/plans/openssl-provider-wit.md` for the
architecture and 13-phase implementation plan, and
`docs/architecture.md` for the standalone version of the design.

Layout
------

```
provider/provider.wit         OSSL_PROVIDER + OSSL_PARAM + algorithm records
keymgmt/keymgmt.wit           OSSL_OP_KEYMGMT (~25 funcs)
signature/signature.wit       OSSL_OP_SIGNATURE (~20 funcs)
asym-cipher/asym-cipher.wit   OSSL_OP_ASYM_CIPHER (~10 funcs)
worlds/provider-abi.wit       the Layer-1 contract (combines all four)
docs/architecture.md          design overview
```

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
