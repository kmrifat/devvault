import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:vault_core/vault_core.dart';
import 'package:vault_s3/vault_s3.dart' show AwsCredentials;

import '../../app/settings_bridge.dart';
import '../../app/settings_window_launcher.dart';
import '../../app/theme.dart';
import '../../data/agent_bridge.dart';
import '../../data/agent_clients.dart';
import '../../data/app_settings.dart';
import '../../data/providers.dart';
import '../../data/sync_controller.dart';
import '../../data/sync_setup.dart';
import '../../data/updates.dart';
import '../../data/vault_session.dart';
import '../../services/credential_store.dart';
import '../../services/updates.dart';
import '../../shared/desktop_ui.dart';
import 'desktop_settings.dart';
import 'settings_layout.dart';

/// The Settings window's engine (⌘, on macOS): `main()` comes here when
/// desktop_multi_window starts it. It asks the main window for a
/// [SettingsSnapshot], runs the Settings UI on providers that mirror the
/// main window's ([settingsWindowOverrides]), then shows the window.
Future<void> runSettingsWindow(SettingsWindowArguments arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  // For pairing codes and reading a recovery key back; never the vault.
  final crypto = await VaultCrypto.init();
  final client = SettingsBridgeClient(const WindowChannelTransport());
  final snapshot = await client.connect();
  final container = ProviderContainer(
    overrides: settingsWindowOverrides(client, snapshot, crypto),
  );
  client.onState = container.read(settingsSnapshotProvider.notifier).set;
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: SettingsWindowApp(initialPane: arguments.pane, client: client),
    ),
  );
  await WidgetsBinding.instance.endOfFrame;
  await (await WindowController.fromCurrentEngine()).show();
}

/// The main window's latest [SettingsSnapshot], in the Settings window.
final settingsSnapshotProvider =
    NotifierProvider<SettingsSnapshotNotifier, SettingsSnapshot>(
      () => throw StateError('Only in the Settings window'),
    );

class SettingsSnapshotNotifier extends Notifier<SettingsSnapshot> {
  SettingsSnapshotNotifier(this._first);

  final SettingsSnapshot _first;

  @override
  SettingsSnapshot build() => _first;

  void set(SettingsSnapshot snapshot) => state = snapshot;
}

final settingsBridgeClientProvider = Provider<SettingsBridgeClient>(
  (ref) => throw StateError('Only in the Settings window'),
);

/// The providers Settings uses, answered from the main window: its
/// snapshot to read, calls over the bridge to change anything.
List<Override> settingsWindowOverrides(
  SettingsBridgeClient client,
  SettingsSnapshot first,
  VaultCrypto crypto,
) {
  T watch<T>(Ref ref, T Function(SettingsSnapshot s) pick) =>
      ref.watch(settingsSnapshotProvider.select(pick));
  return [
    settingsSnapshotProvider.overrideWith(
      () => SettingsSnapshotNotifier(first),
    ),
    settingsBridgeClientProvider.overrideWithValue(client),
    cryptoProvider.overrideWithValue(crypto),
    appSupportDirProvider.overrideWithValue(Directory(first.supportDir)),
    appVersionProvider.overrideWithValue(first.version),
    agentSocketPathProvider.overrideWithValue(first.agentSocket),
    agentHelperPathProvider.overrideWithValue(first.agentHelper),
    agentHelperArgsProvider.overrideWithValue(first.agentHelperArgs),
    initialSettingsProvider.overrideWithValue(first.settings),
    settingsProvider.overrideWith(_RemoteSettings.new),
    updatesProvider.overrideWith(_RemoteUpdates.new),
    updateInstallerProvider.overrideWithValue(
      first.canInstall ? _RemoteInstaller(client) : null,
    ),
    vaultFactsProvider.overrideWith((ref) => watch(ref, (s) => s.vault)),
    vaultActionsProvider.overrideWithValue(_RemoteVault(client, crypto)),
    biometricUnlockProvider.overrideWith(
      (ref) async =>
          watch(ref, (s) => s.biometric) ??
          const BiometricUnlock(null, enabled: false, storable: false),
    ),
    syncSetupProvider.overrideWith(_RemoteSyncSetup.new),
    syncControllerProvider.overrideWith(_RemoteSync.new),
    credentialStoreProvider.overrideWith(
      (ref) => _MirroredCredentialStore(
        degraded: watch(ref, (s) => s.credentialsDegraded),
      ),
    ),
    agentBridgeProvider.overrideWith(_RemoteAgents.new),
  ];
}

SettingsBridgeClient _client(Ref ref) => ref.read(settingsBridgeClientProvider);

class _RemoteSettings extends SettingsNotifier {
  @override
  AppSettings build() =>
      ref.watch(settingsSnapshotProvider.select((s) => s.settings));

  /// Shown here at once; the main window saves it and applies it.
  @override
  void update(AppSettings next) {
    if (next == state) return;
    state = next;
    unawaited(_client(ref).call(SettingsCalls.settings, next.toJson()));
  }
}

class _RemoteUpdates extends UpdatesNotifier {
  @override
  UpdateStatus build() =>
      ref.watch(settingsSnapshotProvider.select((s) => s.updates));

  /// The main window runs the checks.
  @override
  Future<void> checkIfDue() async {}

  @override
  Future<void> checkNow() async {
    await _client(ref).call(SettingsCalls.checkUpdates);
  }

  @override
  void dismiss(AppVersion version) => unawaited(
    _client(ref).call(SettingsCalls.dismissUpdate, version.toString()),
  );
}

class _RemoteInstaller implements UpdateInstaller {
  const _RemoteInstaller(this._client);

  final SettingsBridgeClient _client;

  @override
  Future<void> install(Release release) async {
    await _client.call(SettingsCalls.installUpdate, release.toJson());
  }
}

class _RemoteVault implements VaultActions {
  const _RemoteVault(this._client, this._crypto);

  final SettingsBridgeClient _client;
  final VaultCrypto _crypto;

  @override
  Future<bool> checkPassword(String password) async =>
      await _client.call(SettingsCalls.checkPassword, password) == true;

  @override
  Future<void> changePassword(String newPassword) async {
    await _client.call(SettingsCalls.changePassword, newPassword);
  }

  @override
  Future<RecoveryKey> replaceRecoveryKey() async => RecoveryKey.parse(
    _crypto,
    (await _client.call(SettingsCalls.replaceRecoveryKey))! as String,
  );

  @override
  Future<RecoveryKey> rotateVaultKey(String password) async =>
      RecoveryKey.parse(
        _crypto,
        (await _client.call(SettingsCalls.rotateVaultKey, password))! as String,
      );

  @override
  Future<bool> enableBiometricUnlock({required String reason}) async =>
      await _client.call(SettingsCalls.enableBiometric, reason) == true;

  @override
  Future<void> disableBiometricUnlock() async {
    await _client.call(SettingsCalls.disableBiometric);
  }
}

class _RemoteSyncSetup extends SyncSetupNotifier {
  @override
  SyncSetup? build() =>
      ref.watch(settingsSnapshotProvider.select((s) => s.sync));

  @override
  Future<StorageCapabilities> test(
    SyncSettings settings,
    AwsCredentials credentials,
  ) async => StorageCapabilities.fromJson(
    ((await _client(ref).call(SettingsCalls.testStorage, {
              'settings': settings.toJson(),
              ..._keys(credentials),
            }))!
            as Map)
        .cast<String, Object?>(),
  );

  @override
  Future<void> save(
    SyncSettings settings,
    AwsCredentials credentials,
    StorageCapabilities capabilities,
  ) async {
    await _client(ref).call(SettingsCalls.saveStorage, {
      'settings': settings.toJson(),
      ..._keys(credentials),
      'capabilities': capabilities.toJson(),
    });
  }

  @override
  Future<void> turnOff() async {
    await _client(ref).call(SettingsCalls.turnOffSync);
  }

  static Map<String, Object?> _keys(AwsCredentials credentials) => {
    'access_key_id': credentials.accessKeyId,
    'secret_access_key': credentials.secretAccessKey,
  };
}

/// Settings only asks the main window to sync now; it shows no status.
class _RemoteSync extends SyncController {
  @override
  SyncStatus build() => const SyncOff();

  @override
  Future<SyncReport?> syncNow() async {
    await _client(ref).call(SettingsCalls.syncNow);
    return null;
  }
}

class _RemoteAgents extends AgentBridgeNotifier {
  @override
  AgentBridgeState build() {
    final s = ref.watch(settingsSnapshotProvider);
    return AgentBridgeState(
      otherInstance: s.agentsElsewhere,
      clients: s.clients,
      activity: s.activity,
    );
  }

  @override
  Future<void> revoke(PairedClient client) async {
    await _client(ref).call(SettingsCalls.revokeClient, client.tokenHash);
  }
}

/// The main window's keychain, as far as Settings tells: whether it fell
/// back to memory. Settings never reads or writes keys itself.
class _MirroredCredentialStore extends FallbackCredentialStore {
  _MirroredCredentialStore({required this._degraded})
    : super(MemoryCredentialStore());

  final bool _degraded;

  @override
  bool get isDegraded => _degraded;
}

/// The Settings window: the pane tabs under its title, the pane, ⌘W to
/// close. It closes when the main window locks the vault.
class SettingsWindowApp extends ConsumerStatefulWidget {
  const SettingsWindowApp({
    super.key,
    required this.initialPane,
    required this.client,
  });

  final SettingsPane initialPane;
  final SettingsBridgeClient client;

  /// How far the window's title bar reaches over the pane tabs
  /// (`SettingsWindow.swift`: a transparent, full-size title bar).
  static const titleBarHeight = 28.0;

  /// How often input here is reported to the main window's auto-lock.
  static const activityEvery = Duration(seconds: 5);

  @override
  ConsumerState<SettingsWindowApp> createState() => _SettingsWindowAppState();
}

class _SettingsWindowAppState extends ConsumerState<SettingsWindowApp> {
  /// This window's own channel (`SettingsWindow.swift`): title and close.
  static const _window = MethodChannel('devvault/settings_window');

  late SettingsPane _pane = widget.initialPane;
  DateTime? _reported;

  @override
  void initState() {
    super.initState();
    final client = widget.client;
    client.onShow = (name) => _select(
      SettingsPane.values.where((p) => p.name == name).firstOrNull ?? _pane,
    );
    client.onClose = _close;
    HardwareKeyboard.instance.addHandler(_onKey);
    unawaited(_setTitle());
    // The title bar is AppKit's: it follows DevVault's Appearance, not
    // only the Mac's.
    ref.listenManual(
      settingsProvider.select((s) => s.themeMode),
      (_, mode) => unawaited(_setAppearance(mode)),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  void _select(SettingsPane pane) {
    if (pane == _pane) return;
    setState(() => _pane = pane);
    unawaited(_setTitle());
  }

  Future<void> _setTitle() async {
    try {
      await _window.invokeMethod<void>('setTitle', {'title': _pane.label});
    } on MissingPluginException {
      // Tests.
    }
  }

  Future<void> _setAppearance(ThemeMode mode) async {
    try {
      await _window.invokeMethod<void>('setAppearance', {'mode': mode.name});
    } on MissingPluginException {
      // Tests.
    }
  }

  void _close() => unawaited(_window.invokeMethod<void>('close'));

  bool _onKey(KeyEvent event) {
    _activity();
    return false;
  }

  /// Input here keeps the vault open, like input in the main window.
  void _activity() {
    final now = DateTime.now();
    final reported = _reported;
    if (reported != null &&
        now.difference(reported) < SettingsWindowApp.activityEvery) {
      return;
    }
    _reported = now;
    unawaited(
      widget.client.call(SettingsCalls.activity).catchError((_) => null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(vaultFactsProvider) == null;
    if (locked) _close();
    return MaterialApp(
      title: 'DevVault Settings',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(settingsProvider.select((s) => s.themeMode)),
      // Around the Navigator, so the kits' menus and sheets are themed.
      builder: (context, child) => DesktopTheme(child: child!),
      home: Listener(
        onPointerDown: (_) => _activity(),
        onPointerHover: (_) => _activity(),
        onPointerSignal: (_) => _activity(),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyW, meta: true): _close,
          },
          child: Focus(
            autofocus: true,
            child: Builder(
              builder: (context) => Material(
                color: context.desktopColors.window,
                child: locked
                    ? const SizedBox.shrink()
                    : DesktopSettingsPage(
                        pane: _pane,
                        onSelect: _select,
                        titleBarInset: SettingsWindowApp.titleBarHeight,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
