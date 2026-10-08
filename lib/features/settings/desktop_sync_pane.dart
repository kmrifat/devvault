import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_core/vault_core.dart';

import '../../data/providers.dart' show credentialStoreProvider;
import '../../data/sync_controller.dart';
import '../../data/sync_setup.dart';
import '../../services/credential_store.dart';
import '../../shared/desktop_ui.dart';
import '../pairing/pair_screen.dart' show showPairDevice;
import 'desktop_settings.dart';
import 'desktop_storage_form.dart';
import 'storage_form.dart' show StorageFormModel;

/// What the last connection test said, for the line under the form.
sealed class StorageTestResult {
  const StorageTestResult();
}

class StorageTestPassed extends StorageTestResult {
  const StorageTestPassed(this.capabilities);

  final StorageCapabilities capabilities;
}

class StorageTestFailed extends StorageTestResult {
  const StorageTestFailed(this.message);

  final String message;
}

/// Settings › Sync on desktop (design frame N07b): the sync now running,
/// if any; the storage form; Test Connection and Turn On Sync; and Pair a
/// device. `SyncSettingsScreen` holds the state and does the work.
class DesktopSyncPane extends ConsumerWidget {
  const DesktopSyncPane({
    super.key,
    required this.form,
    required this.setup,
    required this.result,
    required this.busy,
    required this.canSave,
    required this.onTest,
    required this.onSave,
    required this.onTurnOff,
  });

  final StorageFormModel form;
  final SyncSetup? setup;
  final StorageTestResult? result;
  final bool busy;
  final bool canSave;
  final VoidCallback onTest;
  final VoidCallback onSave;
  final VoidCallback onTurnOff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.desktopColors;
    final setup = this.setup;
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    final secondary = TextStyle(
      fontSize: DesktopMetrics.secondarySize,
      color: colors.secondaryText,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sync through an S3-compatible bucket you own. Everything is '
          'encrypted on this ${mac ? 'Mac' : 'computer'} first: the bucket '
          'only ever sees ciphertext and vault.json.',
          style: TextStyle(
            fontSize: DesktopMetrics.cellSize,
            color: colors.text,
          ),
        ),
        const SizedBox(height: 14),
        if (setup != null) ...[
          _CurrentSetup(setup: setup, onTurnOff: onTurnOff),
          const SizedBox(height: 14),
        ],
        DesktopStorageForm(
          model: form,
          footer: switch (result) {
            null => null,
            final result => _ResultLine(result: result),
          },
        ),
        const SizedBox(height: 12),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: Text(
                mac
                    ? 'Keys are kept in the macOS Keychain, never in the '
                          'vault or the bucket.'
                    : 'Keys are kept in this computer’s keychain, never in '
                          'the vault or the bucket.',
                style: secondary,
              ),
            ),
            DesktopButton(
              label: busy ? 'Testing…' : 'Test Connection',
              onPressed: busy ? null : onTest,
            ),
            DesktopButton(
              label: setup == null ? 'Turn On Sync' : 'Save Changes',
              kind: DesktopButtonKind.primary,
              onPressed: busy || !canSave ? null : onSave,
            ),
          ],
        ),
        const SizedBox(height: 16),
        DesktopSettingsBox(
          children: [
            DesktopSettingsRow(
              leading: DesktopIcon(DesktopSymbol.pairDevice, size: 18),
              title: 'Pair a device',
              description:
                  'Hand this storage to another device with a QR code. Never '
                  'the vault key.',
              details: [if (setup == null) 'Turn on sync first.'],
              trailing: DesktopButton(
                label: 'Pair…',
                onPressed: setup == null ? null : () => showPairDevice(context),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The sync this device runs now: where to, Sync Now and Turn Off, and
/// what the storage doesn't enforce.
class _CurrentSetup extends ConsumerWidget {
  const _CurrentSetup({required this.setup, required this.onTurnOff});

  final SyncSetup setup;
  final VoidCallback onTurnOff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.desktopColors;
    final s = setup.settings;
    final warnings = setup.capabilities?.warnings ?? const <String>[];
    final degraded = switch (ref.watch(credentialStoreProvider)) {
      FallbackCredentialStore(isDegraded: true) => true,
      _ => false,
    };
    return DesktopSettingsBox(
      children: [
        DesktopSettingsRow(
          leading: DesktopIcon(
            DesktopSymbol.synced,
            size: 18,
            color: colors.success,
          ),
          title:
              'Syncing with ${s.provider.label} · ${s.bucket}'
              '${s.rootPrefix.isEmpty ? '' : '/${s.rootPrefix}'}',
          details: [
            ...warnings,
            if (degraded)
              'This device has no keychain (on Linux: no Secret Service such '
                  'as GNOME Keyring or KWallet), so the access keys are kept '
                  'only until DevVault quits. Enter them here again after a '
                  'restart.',
          ],
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              DesktopButton(
                label: 'Sync Now',
                onPressed: () =>
                    ref.read(syncControllerProvider.notifier).syncNow(),
              ),
              DesktopButton(
                label: 'Turn Off',
                kind: DesktopButtonKind.destructive,
                onPressed: onTurnOff,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "✓ Connected · conditional writes enforced", or what's limited, or why
/// the connection failed.
class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.result});

  final StorageTestResult result;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final (symbol, tint, title, lines) = switch (result) {
      StorageTestFailed(:final message) => (
        DesktopSymbol.error,
        colors.danger,
        'Connection failed',
        [message],
      ),
      StorageTestPassed(:final capabilities) when capabilities.isRaceFree => (
        DesktopSymbol.success,
        colors.success,
        'Connected · conditional writes enforced',
        const <String>[],
      ),
      StorageTestPassed(:final capabilities) => (
        DesktopSymbol.warning,
        colors.warning,
        'Connected, with a limitation',
        capabilities.warnings,
      ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: DesktopIcon(symbol, size: 13, color: tint),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: DesktopMetrics.cellSize,
                  fontWeight: FontWeight.w500,
                  color: colors.text,
                ),
              ),
              for (final line in lines)
                Text(
                  line,
                  style: TextStyle(
                    fontSize: DesktopMetrics.secondarySize,
                    color: colors.secondaryText,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
