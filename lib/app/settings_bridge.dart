import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_core/vault_core.dart';
import 'package:vault_s3/vault_s3.dart' show AwsCredentials;

import '../data/agent_bridge.dart';
import '../data/agent_clients.dart';
import '../data/app_settings.dart';
import '../data/providers.dart';
import '../data/sync_controller.dart';
import '../data/sync_setup.dart';
import '../data/updates.dart';
import '../data/vault_session.dart';
import '../services/biometric_key_store.dart';
import '../services/credential_store.dart';
import '../services/updates.dart';

/// How the main window and macOS's Settings window talk (⌘,). The Settings
/// window is a second Flutter engine (desktop_multi_window) with its own
/// memory: it never opens the vault. The main window keeps the session,
/// sync, updates and the agent bridge; it sends the Settings window a
/// [SettingsSnapshot] of what Settings shows whenever that changes, and
/// runs what the Settings window asks of it.
///
/// Every message is one JSON string each way. A reply is `{"ok": value}`
/// or `{"error": kind, ...}`; [SettingsBridgeClient] turns an error back
/// into the exception the Settings UI already handles.
///
/// Both engines are in this one process. What crosses is what Settings
/// shows or asks for: the sync access keys (the storage form shows them),
/// a password the user types to check or change it, a new recovery key to
/// show once. Nothing is written to disk or logged on the way.
abstract interface class BridgeTransport {
  /// Starts receiving the other window's calls.
  Future<void> listen(Future<String?> Function(String method, String? body) on);

  /// Calls the other window. Throws when it isn't there.
  Future<String?> call(String method, [String? body]);
}

/// [BridgeTransport] over desktop_multi_window's channel between engines.
class WindowChannelTransport implements BridgeTransport {
  const WindowChannelTransport();

  static const _channel = WindowMethodChannel('devvault/settings');

  @override
  Future<void> listen(
    Future<String?> Function(String method, String? body) on,
  ) => _channel.setMethodCallHandler(
    (call) => on(call.method, call.arguments as String?),
  );

  @override
  Future<String?> call(String method, [String? body]) =>
      _channel.invokeMethod<String>(method, body);
}

/// What Settings shows, as the main window sees it.
@immutable
class SettingsSnapshot {
  const SettingsSnapshot({
    required this.settings,
    required this.supportDir,
    this.version,
    this.canInstall = false,
    this.updates = const UpdateStatus(),
    this.vault,
    this.biometric,
    this.sync,
    this.credentialsDegraded = false,
    this.agentsElsewhere = false,
    this.clients = const [],
    this.activity = const [],
    this.agentSocket,
    this.agentHelper,
  });

  final AppSettings settings;
  final String supportDir;
  final AppVersion? version;

  /// Whether the main window can install an update in place (Sparkle).
  final bool canInstall;
  final UpdateStatus updates;

  /// Null while the vault is locked.
  final VaultFacts? vault;
  final BiometricUnlock? biometric;
  final SyncSetup? sync;
  final bool credentialsDegraded;

  /// [AgentBridgeState.otherInstance].
  final bool agentsElsewhere;
  final List<PairedClient> clients;
  final List<AgentActivity> activity;
  final String? agentSocket;
  final String? agentHelper;

  Map<String, Object?> toJson() => {
    'settings': settings.toJson(),
    'support_dir': supportDir,
    'version': version?.toString(),
    'can_install': canInstall,
    'updates': {...updates.toJson(), 'checking': updates.checking},
    'vault': vault?.toJson(),
    'biometric': switch (biometric) {
      null => null,
      final b => {
        'biometry': b.biometry?.name,
        'unavailable': b.unavailable?.name,
        'enabled': b.enabled,
        'storable': b.storable,
      },
    },
    'sync': switch (sync) {
      null => null,
      final s => {
        'settings': s.settings.toJson(),
        'access_key_id': s.credentials.accessKeyId,
        'secret_access_key': s.credentials.secretAccessKey,
        'capabilities': s.capabilities?.toJson(),
      },
    },
    'credentials_degraded': credentialsDegraded,
    'agents_elsewhere': agentsElsewhere,
    'clients': [for (final c in clients) c.toJson()],
    'activity': [
      for (final a in activity)
        {
          'at': a.at.toUtc().toIso8601String(),
          'client': a.client,
          'action': a.action,
          'detail': a.detail,
          'outcome': a.outcome,
        },
    ],
    'agent_socket': agentSocket,
    'agent_helper': agentHelper,
  };

  factory SettingsSnapshot.fromJson(Map<String, Object?> json) {
    Map<String, Object?>? map(Object? value) =>
        value is Map ? value.cast<String, Object?>() : null;
    final updates = map(json['updates']);
    final biometric = map(json['biometric']);
    final sync = map(json['sync']);
    final vault = map(json['vault']);
    final version = json['version'];
    T? byName<T extends Enum>(List<T> values, Object? name) =>
        values.where((v) => v.name == name).firstOrNull;
    return SettingsSnapshot(
      settings: AppSettings.fromJson(json['settings']),
      supportDir: json['support_dir']! as String,
      version: version is String ? AppVersion.tryParse(version) : null,
      canInstall: json['can_install'] == true,
      updates: UpdateStatus.fromJson(updates)
          .copyWith(checking: updates?['checking'] == true),
      vault: vault == null ? null : VaultFacts.fromJson(vault),
      biometric: biometric == null
          ? null
          : BiometricUnlock(
              byName(Biometry.values, biometric['biometry']),
              unavailable: byName(
                BiometryUnavailable.values,
                biometric['unavailable'],
              ),
              enabled: biometric['enabled'] == true,
              storable: biometric['storable'] == true,
            ),
      sync: sync == null
          ? null
          : SyncSetup(
              settings: SyncSettings.fromJson(map(sync['settings'])!),
              credentials: AwsCredentials(
                accessKeyId: sync['access_key_id']! as String,
                secretAccessKey: sync['secret_access_key']! as String,
              ),
              capabilities: switch (map(sync['capabilities'])) {
                null => null,
                final c => StorageCapabilities.fromJson(c),
              },
            ),
      credentialsDegraded: json['credentials_degraded'] == true,
      agentsElsewhere: json['agents_elsewhere'] == true,
      clients: [
        for (final c in (json['clients'] as List?) ?? const [])
          ?PairedClient.fromJson(c),
      ],
      activity: [
        for (final a in (json['activity'] as List?) ?? const [])
          if (map(a) case final a?)
            AgentActivity(
              at: DateTime.parse(a['at']! as String),
              client: a['client']! as String,
              action: a['action']! as String,
              detail: a['detail']! as String,
              outcome: a['outcome']! as String,
            ),
      ],
      agentSocket: json['agent_socket'] as String?,
      agentHelper: json['agent_helper'] as String?,
    );
  }
}

/// The calls the Settings window makes, by name.
abstract final class SettingsCalls {
  static const snapshot = 'snapshot';
  static const settings = 'settings';
  static const activity = 'activity';
  static const checkUpdates = 'updates.check';
  static const dismissUpdate = 'updates.dismiss';
  static const installUpdate = 'updates.install';
  static const checkPassword = 'vault.checkPassword';
  static const changePassword = 'vault.changePassword';
  static const replaceRecoveryKey = 'vault.replaceRecoveryKey';
  static const rotateVaultKey = 'vault.rotateVaultKey';
  static const enableBiometric = 'biometric.enable';
  static const disableBiometric = 'biometric.disable';
  static const testStorage = 'sync.test';
  static const saveStorage = 'sync.save';
  static const turnOffSync = 'sync.turnOff';
  static const syncNow = 'sync.now';
  static const revokeClient = 'agents.revoke';

  /// The main window's, to the Settings window.
  static const state = 'state';
  static const show = 'show';
  static const close = 'close';
}

/// The main window's end: answers the Settings window from the live
/// providers and keeps it up to date.
class SettingsBridgeHost {
  SettingsBridgeHost(this._ref, this._transport) {
    unawaited(_transport.listen(_handle));
    _ref
      ..listen(settingsProvider, (_, _) => _push())
      ..listen(updatesProvider, (_, _) => _push())
      ..listen(vaultFactsProvider, (_, facts) {
        if (facts == null) {
          unawaited(_send(SettingsCalls.close));
        } else {
          _push();
        }
      })
      ..listen(biometricUnlockProvider, (_, _) => _push())
      ..listen(syncSetupProvider, (_, _) => _push())
      ..listen(agentBridgeProvider, (previous, next) {
        if (previous?.clients != next.clients ||
            previous?.activity != next.activity ||
            previous?.otherInstance != next.otherInstance) {
          _push();
        }
      });
  }

  final Ref _ref;
  final BridgeTransport _transport;

  /// Whether a Settings window has asked for a snapshot since the last
  /// failed send: there's someone to keep up to date.
  bool _connected = false;
  bool _pushQueued = false;

  /// Shows [pane] in the Settings window that's open.
  Future<void> show(String pane) => _send(SettingsCalls.show, pane);

  /// Asks the open Settings window to close.
  Future<void> close() => _send(SettingsCalls.close);

  SettingsSnapshot snapshot() {
    final bridge = _ref.read(agentBridgeProvider);
    return SettingsSnapshot(
      settings: _ref.read(settingsProvider),
      supportDir: _ref.read(appSupportDirProvider).path,
      version: _ref.read(appVersionProvider),
      canInstall: _ref.read(updateInstallerProvider) != null,
      updates: _ref.read(updatesProvider),
      vault: _ref.read(vaultFactsProvider),
      biometric: _ref.read(biometricUnlockProvider).value,
      sync: _ref.read(syncSetupProvider),
      credentialsDegraded: switch (_ref.read(credentialStoreProvider)) {
        FallbackCredentialStore(isDegraded: true) => true,
        _ => false,
      },
      agentsElsewhere: bridge.otherInstance,
      clients: bridge.clients,
      activity: bridge.activity,
      agentSocket: _ref.read(agentSocketPathProvider),
      agentHelper: _ref.read(agentHelperPathProvider),
    );
  }

  /// One snapshot after a burst of changes.
  void _push() {
    if (!_connected || _pushQueued) return;
    _pushQueued = true;
    scheduleMicrotask(() {
      _pushQueued = false;
      unawaited(_send(SettingsCalls.state, jsonEncode(snapshot().toJson())));
    });
  }

  Future<void> _send(String method, [String? body]) async {
    if (!_connected) return;
    try {
      await _transport.call(method, body);
    } on Object {
      // The window closed.
      _connected = false;
    }
  }

  Future<String?> _handle(String method, String? body) async {
    final args = body == null ? null : jsonDecode(body);
    try {
      return jsonEncode({'ok': await _run(method, args)});
    } on BiometricKeyUnavailable catch (e) {
      return jsonEncode({'error': 'biometric', 'code': e.code});
    } on StorageException catch (e) {
      return jsonEncode({
        'error': 'storage',
        'kind': switch (e) {
          StorageAccessDenied() => 'denied',
          StorageNotFound() => 'not_found',
          StorageUnavailable() => 'unavailable',
          PreconditionFailed() => 'precondition',
        },
        'message': e.message,
      });
    } on UpdateCheckFailed catch (e) {
      return jsonEncode({'error': 'update', 'reason': e.reason});
    } on Object {
      // Never the exception's text: it might quote what was asked.
      return jsonEncode({'error': 'failed'});
    }
  }

  Future<Object?> _run(String method, Object? args) async {
    Map<String, Object?> map() => (args! as Map).cast<String, Object?>();
    final vault = _ref.read(vaultActionsProvider);
    switch (method) {
      case SettingsCalls.snapshot:
        _connected = true;
        return snapshot().toJson();
      case SettingsCalls.settings:
        _ref.read(settingsProvider.notifier).update(AppSettings.fromJson(args));
      case SettingsCalls.activity:
        _ref.read(userActivityProvider.notifier).touch();
      case SettingsCalls.checkUpdates:
        await _ref.read(updatesProvider.notifier).checkNow();
      case SettingsCalls.dismissUpdate:
        final version = AppVersion.tryParse(args! as String);
        if (version != null) {
          _ref.read(updatesProvider.notifier).dismiss(version);
        }
      case SettingsCalls.installUpdate:
        final release = Release.fromJson(args);
        final installer = _ref.read(updateInstallerProvider);
        if (release != null && installer != null) {
          await installer.install(release);
        }
      case SettingsCalls.checkPassword:
        return vault.checkPassword(args! as String);
      case SettingsCalls.changePassword:
        await vault.changePassword(args! as String);
      case SettingsCalls.replaceRecoveryKey:
        return _shown(await vault.replaceRecoveryKey());
      case SettingsCalls.rotateVaultKey:
        return _shown(await vault.rotateVaultKey(args! as String));
      case SettingsCalls.enableBiometric:
        return vault.enableBiometricUnlock(reason: args! as String);
      case SettingsCalls.disableBiometric:
        await vault.disableBiometricUnlock();
      case SettingsCalls.testStorage:
        final call = map();
        final capabilities = await _ref
            .read(syncSetupProvider.notifier)
            .test(
              SyncSettings.fromJson(call['settings']! as Map<String, Object?>),
              _credentials(call),
            );
        return capabilities.toJson();
      case SettingsCalls.saveStorage:
        final call = map();
        await _ref
            .read(syncSetupProvider.notifier)
            .save(
              SyncSettings.fromJson(call['settings']! as Map<String, Object?>),
              _credentials(call),
              StorageCapabilities.fromJson(
                call['capabilities']! as Map<String, Object?>,
              ),
            );
      case SettingsCalls.turnOffSync:
        await _ref.read(syncSetupProvider.notifier).turnOff();
      case SettingsCalls.syncNow:
        unawaited(_ref.read(syncControllerProvider.notifier).syncNow());
      case SettingsCalls.revokeClient:
        final bridge = _ref.read(agentBridgeProvider.notifier);
        final client = _ref
            .read(agentBridgeProvider)
            .clients
            .where((c) => c.tokenHash == args)
            .firstOrNull;
        if (client != null) await bridge.revoke(client);
      default:
        throw ArgumentError.value(method, 'method');
    }
    return null;
  }

  /// The key's text for the Settings window to show once; the key itself
  /// is wiped here.
  static String _shown(RecoveryKey key) {
    try {
      return key.toDisplayString();
    } finally {
      key.dispose();
    }
  }

  static AwsCredentials _credentials(Map<String, Object?> call) =>
      AwsCredentials(
        accessKeyId: call['access_key_id']! as String,
        secretAccessKey: call['secret_access_key']! as String,
      );
}

/// The Settings window's end: the main window's snapshot as it changes,
/// and calls into the main window.
class SettingsBridgeClient {
  SettingsBridgeClient(this._transport);

  final BridgeTransport _transport;

  /// A new snapshot from the main window.
  void Function(SettingsSnapshot snapshot)? onState;

  /// The main window wants [pane] on show.
  void Function(String pane)? onShow;

  /// The main window wants this window closed (the vault locked).
  VoidCallback? onClose;

  /// Starts listening and fetches the first snapshot.
  Future<SettingsSnapshot> connect() async {
    await _transport.listen((method, body) async {
      switch (method) {
        case SettingsCalls.state:
          onState?.call(
            SettingsSnapshot.fromJson(
              (jsonDecode(body!) as Map).cast<String, Object?>(),
            ),
          );
        case SettingsCalls.show:
          onShow?.call(body ?? '');
        case SettingsCalls.close:
          onClose?.call();
      }
      return null;
    });
    final json = await call(SettingsCalls.snapshot);
    return SettingsSnapshot.fromJson((json! as Map).cast<String, Object?>());
  }

  /// Calls the main window and returns its answer. Throws what the main
  /// window's providers threw, as far as the Settings UI tells them apart.
  Future<Object?> call(String method, [Object? args]) async {
    final reply = await _transport.call(
      method,
      args == null ? null : jsonEncode(args),
    );
    final map = (jsonDecode(reply!) as Map).cast<String, Object?>();
    if (!map.containsKey('error')) return map['ok'];
    throw switch (map['error']) {
      'biometric' => BiometricKeyUnavailable(map['code']! as String),
      'storage' => switch (map['kind']) {
        'denied' => StorageAccessDenied(map['message']! as String),
        'not_found' => StorageNotFound(map['message']! as String),
        'unavailable' => StorageUnavailable(map['message']! as String),
        _ => PreconditionFailed(map['message']! as String),
      },
      'update' => UpdateCheckFailed(map['reason']! as String),
      _ => const BridgeFailure(),
    };
  }
}

/// The main window couldn't do what the Settings window asked.
class BridgeFailure implements Exception {
  const BridgeFailure();

  @override
  String toString() => 'BridgeFailure';
}
