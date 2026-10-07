# biometric_key

The native half of DevVault's device-bound unlock (SPEC §9.1). The Dart API is
`ChannelBiometricKeyStore` in `lib/services/biometric_key_store.dart`.

| Platform | Where the vault key lives |
|---|---|
| iOS, macOS | A Keychain item with `.biometryCurrentSet` and `WhenPasscodeSetThisDeviceOnly`. The enrolment state is saved with it, so a changed enrolment reads as `gone`. |
| Android | An AES-256-GCM Keystore key (StrongBox when available) with per-use `BIOMETRIC_STRONG` auth and `setInvalidatedByBiometricEnrollment(true)`. It wraps the vault key; the ciphertext lives in app-private shared preferences. |

macOS needs the data protection keychain, which needs a signed build with a
`keychain-access-groups` entitlement (P1-24). Unsigned builds report no
biometrics, so the setting doesn't show.

Errors carry a code only, never a message: `gone`, `cancelled`, `keychain-<status>`,
`auth-<code>`, `no-activity`.
