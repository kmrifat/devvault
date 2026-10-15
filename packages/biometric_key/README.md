# biometric_key

The native half of DevVault's device-bound unlock (SPEC §9.1). The Dart API is
`ChannelBiometricKeyStore` in `lib/services/biometric_key_store.dart`.

| Platform | Where the vault key lives |
|---|---|
| iOS, macOS | A Keychain item with `.biometryCurrentSet` and `WhenPasscodeSetThisDeviceOnly`. Beside it, an unprotected marker item (`…biometric-key.state`) holds the enrolment state the key was stored under, so `has` and a changed enrolment (read as `gone`) never need the protected item, which a device's Secure Enclave won't show without a prompt. |
| Android | An AES-256-GCM Keystore key (StrongBox when available) with per-use `BIOMETRIC_STRONG` auth and `setInvalidatedByBiometricEnrollment(true)`. It wraps the vault key; the ciphertext lives in app-private shared preferences. |

macOS needs the data protection keychain, which needs a build signed with
`com.apple.application-identifier` and `keychain-access-groups`, and those
need a Developer ID provisioning profile embedded in the app
(`docs/release.md`). A Developer ID signature alone isn't enough.
`canStore` says whether this build has them: without them the Touch ID
setting shows, switched off, with the reason.

Methods: `biometry`, `canStore`, `has`, `save`, `read`, `delete`. Errors
carry a code only, never a message: `gone`, `cancelled`, `keychain-<status>`,
`auth-<code>`, `no-activity`.
