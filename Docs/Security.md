# Transport security and pinning

[简体中文](Security.zh-Hans.md) · [Documentation index](README.md)

TLS system trust is the correct default for most Apps. Use pinning only when an explicit security requirement exists and the service has a tested certificate-rotation process. A broken pin can prevent every user from reaching the backend.

## Certificate pinning

`CertificatePinningEvaluator` compares the leaf certificate's DER data for selected hosts after normal system trust succeeds.

```swift
let evaluator = CertificatePinningEvaluator(pinnedCertificates: [
    "api.example.com": [currentCertificateDER, nextCertificateDER]
])
let delegate = ServerTrustSessionDelegate(evaluator: evaluator)
let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
```

Use a dedicated session for the backend that needs pinning. Hosts without pins use normal system handling through the evaluator. Keep at least the active and next certificate pins during rotation.

## Public-key hash pinning

`PublicKeyHashPinningEvaluator` compares SHA-256 hashes of leaf public-key bytes. It is useful when a certificate may change while the public key remains stable.

```swift
let evaluator = PublicKeyHashPinningEvaluator(pinnedHashes: [
    "api.example.com": [currentPublicKeyHash, backupPublicKeyHash]
])
let delegate = ServerTrustSessionDelegate(evaluator: evaluator)
let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
```

Pins are `Data` values. Derive and verify them in a controlled build/release process; do not fetch a new pin from the same untrusted network path at runtime.

## Operational checklist

- Retain a backup pin before any certificate/key change.
- Test the next pin against staging before production rotation.
- Monitor pinning failures separately from ordinary transport errors.
- Define an emergency release process for a lost or compromised pin.
- Keep pinning scoped to the backend session that requires it.

Pinning strengthens one part of transport trust; it does not replace HTTPS, secure token storage, request authorization, input validation, or privacy review.
