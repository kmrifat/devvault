# device_privacy

The native half of DevVault's mobile privacy (P3-06).

| | iOS | Android |
|---|---|---|
| App switcher | A blur over every window while the scene is inactive | `FLAG_SECURE` on the activity: no thumbnail in Recents, no screenshots or screen recording |
| Copied secrets | `UIPasteboard` items marked `localOnly` (no Universal Clipboard) with an `expirationDate` | `ClipDescription` extra `android.content.extra.IS_SENSITIVE`, so the clipboard preview hides it |

The Dart side is `ChannelSensitiveClipboard` in `lib/services/clipboard_guard.dart`.
DevVault still clears the clipboard itself after the chosen time.
