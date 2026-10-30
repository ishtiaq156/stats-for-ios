---
status: accepted
---

# Replace the shared setup key with per-phone pairing

The existing QR flow gives every phone the same long-lived key, so the Mac cannot identify or revoke one phone. The redesigned companion will use a temporary five-digit code with SPAKE2 and key confirmation to enroll one phone per session, then store a distinct high-entropy credential for that phone. This preserves short-code pairing without making the code the permanent secret. Existing phones must pair again, and the pairing implementation needs protocol review because the proposed open-source SPAKE2 library is not independently audited.

The exchange follows [RFC 9382](https://datatracker.ietf.org/doc/html/rfc9382) and uses the [RustCrypto SPAKE2 implementation](https://docs.rs/spake2/0.4.0/spake2/), which explicitly notes its audit limitation.
