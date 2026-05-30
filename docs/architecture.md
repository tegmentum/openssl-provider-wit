Architecture
============

Goal
----

Make OpenSSL 3 provider plugins composable as wasm components. The
first concrete use case is PKCS#11-backed private keys (so the TLS
handshake's `SSL_CTX_use_PrivateKey` can reference an HSM key without
ever materializing it in wasm memory), but the architecture explicitly
leaves room for any native OpenSSL 3 provider to be re-targeted.

Layered design
--------------

```
┌──────────────────────────────────────┐
│  openssl-wasm                        │  Layer 0  (the consumer)
│  TLS/x509/etc., patched to load      │
│  providers through WIT instead of    │
│  dlopen                              │
└────────────────┬─────────────────────┘
                 │ openssl:provider-abi   ← THIS REPO (Layer 1)
                 ▼                         full ABI mirror
┌──────────────────────────────────────┐
│  simple-provider-adapter             │  Layer 2  (convenience)
│  exports: openssl:provider-abi       │
│  imports: tegmentum:key-backend      │
│  Handles keymgmt/signature/asym      │
│  boilerplate on behalf of backends   │
│  that don't care about the full ABI  │
└────────────────┬─────────────────────┘
                 │ tegmentum:key-backend  ← Layer 3 narrow contract
                 ▼                         (separate repo)
┌──────────────────────────────────────┐
│  pkcs11-bridge                       │  Layer 3 backend (one of N)
│  exports: tegmentum:key-backend      │
│  imports: pkcs11:host                │
└────────────────┬─────────────────────┘
                 │ pkcs11:host            ← Layer 4 (varies by deploy)
                 ▼
   ┌────────────────────────────────────────────────────────────┐
   │  Standalone:  pkcs11-wasm-host (Rust, wasmtime + dlopen)   │
   │  Browser:     pkcs11-gateway-adapter (ws-gateway RPC)      │
   │  Browser opt: pkcs11-webauthn-adapter (FIDO2)              │
   │  Browser opt: pkcs11-webcrypto-adapter (SubtleCrypto)      │
   └────────────────────────────────────────────────────────────┘
```

Why two layers (full ABI + narrow contract)?
--------------------------------------------

A "power" backend can target Layer 1 directly when it needs the full
OpenSSL provider surface (registering custom mechanisms, exposing
encoders/decoders, controlling param matrices). A typical backend
just wants "give me a TLS private key for this URI" -- that's the
narrow `tegmentum:key-backend` contract. `simple-provider-adapter`
handles the boring 80% (OSSL_PARAM marshalling, mechanism enum
translation, resource lifecycle) so the typical-case backend stays
small.

Scope of Layer 1 (initial)
--------------------------

Three OpenSSL 3 operation classes are enough for TLS server/client +
mTLS:

- `OSSL_OP_KEYMGMT`    create/import/export key handles, query attrs
- `OSSL_OP_SIGNATURE`  sign/verify (RSA / ECDSA / Ed25519)
- `OSSL_OP_ASYM_CIPHER` RSA encrypt/decrypt (TLS 1.2 RSA key exchange)

Operations explicitly deferred to backfill phases (Phase 8):
`OSSL_OP_KEY_EXCHANGE` (ECDH; needed for TLS 1.3 -- promote to Phase 1
if TLS 1.3 server-side mTLS shows up early), `OSSL_OP_KDF`,
`OSSL_OP_MAC`, `OSSL_OP_DIGEST`, `OSSL_OP_CIPHER`, `OSSL_OP_KEM`,
`OSSL_OP_RAND`, `OSSL_OP_ENCODER` / `OSSL_OP_DECODER`, `OSSL_OP_STORE`.

OSSL_PARAM modeling
-------------------

The C API uses untyped data + size + a type code. WIT needs a tagged
variant. We start with the ~10 types TLS actually uses:

```
variant ossl-param-value {
  utf8-string(string),
  octet-string(list<u8>),
  int32(s32),
  int64(s64),
  uint32(u32),
  uint64(u64),
  big-int(list<u8>),         // OPENSSL_BN serialized big-endian
  double-precision(float64),
  octet-string-ptr(list<u8>),// hash-by-value, semantically a pointer
  end,                       // OSSL_PARAM_END terminator marker
}
```

Unknown types fall back to `octet-string` so adding mechanism support
later doesn't require an ABI bump.

Callback direction
------------------

OpenSSL gives the provider a callback table (`OSSL_FUNC_core_*`) for
things like getting the core provider context, BIO ops, etc. These
need to flow back FROM openssl-wasm TO the provider component -- the
reverse direction of most plumbing here. They land as WIT exports on
openssl-wasm and matching imports on the provider component.

Pinned OpenSSL version
----------------------

OpenSSL **3.6.2** (release 2026-04-07).

`<openssl/core_dispatch.h>` SHA-1:
`c475666c52be37e02f0236cbe80ae3faaf54ed8b`.

Tracking newer OpenSSL: provider ABI is stable across 3.x minor
releases but expanding (new `OSSL_FUNC_*` IDs land as new minors).
When bumping the pinned version, audit `core_dispatch.h` for added
function IDs and bump the corresponding interface's package version.

References
----------

- OpenSSL 3 provider docs: https://docs.openssl.org/3.0/man7/provider/
- `<openssl/core_dispatch.h>` (canonical function ID list)
- `<openssl/core.h>` (OSSL_PARAM, OSSL_ALGORITHM, OSSL_DISPATCH)
- python-wasm `plans/openssl-provider-wit.md` -- 13-phase implementation plan
