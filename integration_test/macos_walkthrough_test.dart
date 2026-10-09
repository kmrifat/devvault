// P1-25: a walk through everything built so far, in the real macOS app,
// the way a user would: taps, typing, the menu bar's commands, keyboard
// navigation and mouse drags, in the desktop layout with its native
// window.
//
//   flutter test integration_test/macos_walkthrough_test.dart -d macos
//
// It never touches the owner's vault, settings or keychain: the app is
// built with the same provider overrides the widget tests use, pointed at
// a fresh temporary folder, with in-memory or recording fakes for the
// keychain, notifications, save/open dialogs, Finder and the browser.
// Crypto is the real libsodium, at the real Argon2id cost. The system
// clipboard is real: only made-up values are copied, and it is left
// empty.
//
// Two things are simulated rather than sent through macOS: the menu bar
// owns ⌘ shortcuts there and a synthesized key never reaches AppKit, so
// [_Walk.command] selects the menu item with that shortcut, as AppKit
// would; and Return in a text field arrives as the field's input action.
// Idle time for auto-lock is moved on the clock, not waited out.
//
// Each step takes a screenshot (the app's root, rendered to PNG) into a
// folder in the app's sandbox, `~/Library/Containers/
// com.binarycastle.devvault/Data/tmp/devvault-walkthrough-<time>/`,
// printed at the start and the end. Product problems
// found on the 2026-10-09 run are checked with [knownIssue]: they are
// logged, not failed, and listed in docs/acceptance/macos-walkthrough.md.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cred_parsers/cred_parsers.dart';
import 'package:devvault/app/app.dart';
import 'package:devvault/app/desktop_shell.dart'
    show ShellStatusBar, ShellToolbar;
import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/core/notification_plan.dart';
import 'package:devvault/data/agent_bridge.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/sync_controller.dart';
import 'package:devvault/data/sync_setup.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/create_vault/recovery_kit_card.dart';
import 'package:devvault/features/expiry/desktop_expiry_table.dart';
import 'package:devvault/features/expiry/expiry_screen.dart';
import 'package:devvault/features/import/import_dialog.dart';
import 'package:devvault/features/import/import_draft.dart';
import 'package:devvault/features/pairing/pair_screen.dart';
import 'package:devvault/features/search/quick_open.dart';
import 'package:devvault/features/settings/new_recovery_kit_dialog.dart';
import 'package:devvault/features/vault/desktop_inspector.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:devvault/features/vault/vault_sidebar.dart';
import 'package:devvault/services/credential_store.dart';
import 'package:devvault/services/file_import.dart';
import 'package:devvault/services/file_saver.dart';
import 'package:devvault/services/folder_revealer.dart';
import 'package:devvault/services/link_opener.dart';
import 'package:devvault/services/notifications.dart';
import 'package:devvault/services/recovery_kit.dart';
import 'package:devvault/services/window.dart';
import 'package:devvault/shared/desktop_ui.dart'
    show
        DesktopButton,
        DesktopFormRow,
        DesktopIconButton,
        DesktopPopup,
        DesktopThemeContext;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:vault_core/vault_core.dart';

import 'walkthrough_fixtures.dart';

// ---------------------------------------------------------------------------
// Test data. Every value here is made up for this test.
// ---------------------------------------------------------------------------

const _password = 'walkthrough horse battery staple';
const _wrongPassword = 'not the walkthrough password';
const _newPassword = 'walkthrough second passphrase';
const _fixturePassword = 'test-password'; // packages/cred_parsers fixtures
const _soonToken = 'fake-walkthrough-token-0001';
const _expiredToken = 'fake-walkthrough-token-0002';

/// One file of each type the importer reads (D04 / N04).
class _ImportCase {
  const _ImportCase(
    this.file,
    this.type, {
    this.secrets = const {},
    this.required = const {},
    this.shows = const [],
  });

  final String file;
  final ItemType type;

  /// Passwords the sheet asks for, by request key.
  final Map<String, String> secrets;

  /// Required fields the file doesn't hold, by field key.
  final Map<String, String> required;

  /// Text the sheet must show, besides every fact the parser reads.
  final List<String> shows;
}

const _imports = [
  _ImportCase(
    'AuthKey_TESTKEY123.p8',
    ItemType.appleAuthKey,
    required: {'team_id': 'TESTTEAM01'},
    shows: ['TESTKEY123', 'Required · not in the file'],
  ),
  _ImportCase(
    'legacy.p12',
    ItemType.appleCertificate,
    secrets: {'password': _fixturePassword},
    shows: ['Apple Development', 'Keep the password with the item'],
  ),
  _ImportCase('development.mobileprovision', ItemType.provisioningProfile),
  _ImportCase(
    'test.jks',
    ItemType.androidKeystore,
    secrets: {'store_password': _fixturePassword},
  ),
  _ImportCase('google-services.json', ItemType.firebaseConfig),
  _ImportCase('GoogleService-Info.plist', ItemType.firebaseConfig),
  _ImportCase('service-account.json', ItemType.gcpServiceAccount),
  _ImportCase(
    'client_secret_000000000000-test.apps.googleusercontent.com.json',
    ItemType.oauthClient,
  ),
  _ImportCase('id_ed25519', ItemType.sshKey),
];

// ---------------------------------------------------------------------------
// Fakes for everything that would leave the app's temp folder.
// ---------------------------------------------------------------------------

/// Hands the import sheet whatever files the test queues up.
class _Opener implements FileOpener {
  final queue = <List<PickedFile>>[];

  @override
  Future<List<PickedFile>> pick() async =>
      queue.isEmpty ? const [] : queue.removeAt(0);
}

/// "Saves" into the walkthrough folder instead of opening a save dialog.
class _Saver implements FileSaver {
  _Saver(this.dir);

  final Directory dir;
  final saved = <String, Uint8List>{};

  @override
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
  }) async {
    saved[fileName] = Uint8List.fromList(bytes);
    File('${dir.path}/saved-$fileName').writeAsBytesSync(bytes);
    return true;
  }
}

class _Printer implements DocumentPrinter {
  final printed = <String>[];

  @override
  Future<bool> printPdf(Uint8List bytes, {required String name}) async {
    printed.add(name);
    return true;
  }
}

class _Revealer implements FolderRevealer {
  final revealed = <String>[];

  @override
  bool get isSupported => true;

  @override
  Future<void> reveal(Directory folder) async => revealed.add(folder.path);
}

class _Links implements LinkOpener {
  final opened = <Uri>[];

  @override
  Future<void> open(Uri link) async => opened.add(link);
}

/// Records what would be handed to macOS's notification centre.
class _Alerts implements AlertScheduler {
  final scheduled = <PlannedAlert>[];
  final cancelled = <int>[];
  int permissionAsks = 0;

  @override
  tz.Location get location => tz.UTC;

  @override
  Future<bool> requestPermission() async {
    permissionAsks++;
    return true;
  }

  @override
  Future<void> schedule(PlannedAlert alert) async => scheduled.add(alert);

  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}

// ---------------------------------------------------------------------------
// The walkthrough.
// ---------------------------------------------------------------------------

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // The roundtrip workflow runs every integration test on every
  // platform; this one drives the macOS menu bar and toolbar, so it only
  // runs on macOS.
  testWidgets(
    'macOS walkthrough: everything built so far',
    (tester) async {
      final w = _Walk(tester, binding);
      await w.setUp();
      try {
        await w.run();
      } finally {
        await w.tearDown();
      }
      w.report();
      expect(
        w.failures,
        isEmpty,
        reason: 'steps failed for reasons not recorded as known issues',
      );
    },
    skip: !Platform.isMacOS,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

/// What one step of the walkthrough found.
class _Result {
  _Result(this.name);

  final String name;
  bool passed = true;
  final notes = <String>[];
}

class _Walk {
  _Walk(this.tester, this.binding);

  final WidgetTester tester;
  final IntegrationTestWidgetsFlutterBinding binding;

  late final Directory out;
  late final Directory support;
  late final Directory bucket;
  late final _Saver saver;
  final opener = _Opener();
  final printer = _Printer();
  final revealer = _Revealer();
  final links = _Links();
  final alerts = _Alerts();
  final keychain = MemoryCredentialStore();
  final shotKey = GlobalKey();

  /// Added to the wall clock: moves "idle time" without waiting for it.
  Duration skew = Duration.zero;
  DateTime now() => DateTime.now().add(skew);

  String password = _password;
  int _shot = 0;
  final results = <_Result>[];
  final failures = <String>[];
  final issues = <String>[];
  final errors = <String>[];
  void Function(FlutterErrorDetails)? _onError;

  // -------------------------------------------------------------------------
  // Set-up and tear-down.
  // -------------------------------------------------------------------------

  Future<void> setUp() async {
    final stamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
    out = Directory('${Directory.systemTemp.path}/devvault-walkthrough-$stamp')
      ..createSync(recursive: true);
    support = Directory('${out.path}/app-support')..createSync();
    bucket = Directory('${out.path}/bucket')..createSync();
    saver = _Saver(out);
    _log('Screenshots and saved files: ${out.path}');

    // Everything the app reports through FlutterError (overflows, build
    // errors) is a finding: collect it instead of failing at the first.
    _onError = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString().split('\n').first;
      final where = results.isEmpty ? 'start' : results.last.name;
      errors.add('[$where] $text');
      _log('FLUTTER ERROR during "$where": $text');
    };

    await initWindow();
    final crypto = await VaultCrypto.init();
    await tester.pumpWidget(
      RepaintBoundary(
        key: shotKey,
        child: ProviderScope(
          overrides: [
            clockProvider.overrideWithValue(now),
            appSupportDirProvider.overrideWithValue(support),
            deviceIdProvider.overrideWithValue(
              '00000000-0000-4000-8000-00000000a11c',
            ),
            cryptoProvider.overrideWithValue(crypto),
            credentialStoreProvider.overrideWithValue(keychain),
            alertSchedulerProvider.overrideWithValue(alerts),
            alertDebounceProvider.overrideWithValue(
              const Duration(milliseconds: 200),
            ),
            fileOpenerProvider.overrideWithValue(opener),
            fileSaverProvider.overrideWithValue(saver),
            documentPrinterProvider.overrideWithValue(printer),
            folderRevealerProvider.overrideWithValue(revealer),
            linkOpenerProvider.overrideWithValue(links),
            // Agents get a socket in the test's own folder, never the
            // app's real one.
            agentSocketPathProvider.overrideWithValue(
              '${Directory.systemTemp.path}/dvw-$stamp.sock',
            ),
            agentHelperPathProvider.overrideWithValue(
              '/Applications/DevVault.app/Contents/Helpers/devvault-mcp',
            ),
            // Sync: a folder stands in for the bucket.
            storageBackendFactoryProvider.overrideWithValue(
              (settings, credentials) => LocalDirBackend(bucket),
            ),
            storageProbeProvider.overrideWithValue(
              (settings, credentials, prefix) async => StorageCapabilities.full,
            ),
            pairingOpsLimitProvider.overrideWithValue(KdfParams.minOpsLimit),
            pairingMemLimitProvider.overrideWithValue(8 * 1024 * 1024),
          ],
          child: const DevVaultApp(
            initialLocation: Routes.unlock,
            layout: AppLayout.desktop,
            nativeWindow: true,
          ),
        ),
      ),
    );
    await settle();
  }

  Future<void> tearDown() async {
    // Leave nothing behind: the clipboard empty, the vault locked, the
    // agents' socket closed.
    try {
      await Clipboard.setData(const ClipboardData(text: ''));
    } on Object {
      // Nothing to clear.
    }
    try {
      container.read(settingsProvider.notifier).setAgentsEnabled(false);
      container.read(vaultSessionProvider.notifier).lock();
      await settle();
    } on Object {
      // The app is already gone.
    }
    FlutterError.onError = _onError;
    // The vault's folder holds only made-up items; the screenshots stay.
    if (support.existsSync()) support.deleteSync(recursive: true);
    if (bucket.existsSync()) bucket.deleteSync(recursive: true);
  }

  // -------------------------------------------------------------------------
  // Steps, results and screenshots.
  // -------------------------------------------------------------------------

  Future<void> step(String name, Future<void> Function() body) async {
    final result = _Result(name);
    results.add(result);
    _log('── $name');
    try {
      await body();
    } on Object catch (e, stack) {
      result.passed = false;
      final message = e.toString().split('\n').take(6).join(' | ');
      failures.add('$name: $message');
      _log('STEP FAILED: $name: $message\n$stack');
      await shot('FAILED-${_slug(name)}');
      _dumpTexts();
      await _recover();
    }
  }

  /// A product problem seen on the recorded run: logged and listed, not
  /// failed, so the walkthrough documents it and goes on.
  void knownIssue(String id, bool holds, String expectation) {
    final line = '$id: $expectation';
    if (holds) {
      _log('known issue $id no longer reproduces: $expectation');
      results.last.notes.add('$id fixed?');
      return;
    }
    issues.add(line);
    results.last.notes.add(id);
    _log('KNOWN ISSUE $line');
  }

  void note(String text) {
    results.last.notes.add(text);
    _log('note: $text');
  }

  Future<void> shot(String name) async {
    await tester.pump();
    final number = (++_shot).toString().padLeft(2, '0');
    final file = File('${out.path}/$number-$name.png');
    try {
      final boundary =
          shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ratio = tester.view.devicePixelRatio;
      final image = await boundary.toImage(pixelRatio: ratio);
      // The sidebar is see-through: macOS draws its vibrancy behind the
      // Flutter view. Lay the sidebar's own colour under the picture so
      // the PNG reads as the window does.
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..drawColor(_backdrop(), BlendMode.src)
        ..drawImage(image, Offset.zero, Paint());
      final flat = await recorder.endRecording().toImage(
        image.width,
        image.height,
      );
      image.dispose();
      final png = await flat.toByteData(format: ui.ImageByteFormat.png);
      flat.dispose();
      file.writeAsBytesSync(png!.buffer.asUint8List());
    } on Object catch (e) {
      _log('screenshot $name failed: $e');
    }
  }

  Color _backdrop() {
    final navigators = find.byType(Navigator).evaluate();
    if (navigators.isEmpty) return const Color(0x00000000);
    return navigators.first.desktopColors.sidebar;
  }

  void report() {
    _log('');
    _log('================ WALKTHROUGH RESULTS ================');
    for (final r in results) {
      final notes = r.notes.isEmpty ? '' : '  (${r.notes.join('; ')})';
      _log('${r.passed ? 'PASS' : 'FAIL'}  ${r.name}$notes');
    }
    _log('Known issues seen: ${issues.length}');
    for (final i in issues) {
      _log('  - $i');
    }
    _log('Flutter errors reported: ${errors.length}');
    for (final e in errors) {
      _log('  - $e');
    }
    _log('Unexpected failures: ${failures.length}');
    for (final f in failures) {
      _log('  - $f');
    }
    _log('Screenshots: ${out.path}');
    _log('=====================================================');
  }

  static void _log(String line) {
    // ignore: avoid_print
    print('[walkthrough] $line');
  }

  static String _slug(String s) =>
      s.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-');

  void _dumpTexts() {
    final texts = <String>{
      for (final e in find.byType(Text).evaluate())
        (e.widget as Text).data ?? '',
    }..removeWhere((t) => t.isEmpty);
    _log('on screen: ${texts.take(80).join(' | ')}');
  }

  /// After a failed step: close sheets and menus and go back to the vault.
  Future<void> _recover() async {
    try {
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle();
      }
      final navigator = _navigator;
      navigator?.popUntil((route) => route.isFirst);
      await settle();
      if (session is Locked) await unlock(password);
      router.go(Routes.vault());
      await settle();
    } on Object catch (e) {
      _log('recovery failed: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Helpers.
  // -------------------------------------------------------------------------

  ProviderContainer get container =>
      ProviderScope.containerOf(tester.element(find.byType(DevVaultApp)));

  VaultSession get session => container.read(vaultSessionProvider);

  VaultIndex get index => (session as Unlocked).index;

  GoRouter get router => GoRouter.of(
    tester.element(find.byType(Navigator, skipOffstage: false).last),
  );

  NavigatorState? get _navigator {
    final navigators = find.byType(Navigator).evaluate().toList();
    if (navigators.isEmpty) return null;
    return (navigators.first as StatefulElement).state as NavigatorState;
  }

  String get location => router.state.uri.toString();

  Item item(String title) => index.all.firstWhere((i) => i.title == title);

  /// Pumps frames until nothing is scheduled, or [max] has passed (sync's
  /// spinner and toasts keep animating for a while).
  Future<void> settle([Duration max = const Duration(seconds: 5)]) async {
    try {
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        max,
      );
    } on FlutterError {
      // Still animating; that's fine for a live app.
    }
  }

  /// Real time and frames until [done], or fails after [within].
  Future<void> until(
    bool Function() done, {
    Duration within = const Duration(seconds: 20),
    String what = 'condition',
  }) async {
    final deadline = DateTime.now().add(within);
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TestFailure('Timed out waiting for $what');
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();
  }

  /// An icon button by its tooltip (its tooltip, once shown, carries the
  /// same label, so a semantics finder could pick the bubble instead).
  Finder iconButton(String tooltip) => find.byWidgetPredicate(
    (w) => w is DesktopIconButton && w.tooltip == tooltip,
  );

  /// Taps with a finger by default: a synthesized mouse stays where it
  /// clicked, and hovering keeps a toast open (design doc › toasts).
  Future<void> tap(Finder finder, {PointerDeviceKind? kind}) async {
    expect(finder, findsAtLeast(1), reason: 'nothing to tap: $finder');
    await tester.ensureVisible(finder.first);
    await tester.pump();
    await tester.tap(finder.first, kind: kind ?? PointerDeviceKind.touch);
    await settle();
  }

  Future<void> tapText(String text) => tap(find.text(text).last);

  Future<void> rightClick(Finder finder) async {
    await tester.ensureVisible(finder.first);
    await tester.pump();
    await tester.tap(
      finder.first,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await settle();
  }

  Future<void> press(LogicalKeyboardKey key, {bool shift = false}) async {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await settle();
  }

  /// Return in the focused text field (macOS sends it as the field's
  /// input action, not as a key event).
  Future<void> submit() async {
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle();
  }

  Future<void> type(Finder field, String text) async {
    final editable = find.descendant(
      of: field,
      matching: find.byType(EditableText),
      matchRoot: true,
    );
    await tester.ensureVisible(editable.first);
    // The text goes to the live input connection: make sure it's this
    // field's, even if the binding thinks it already is (a click on a
    // button in between closes it).
    binding.focusedEditable = null;
    await tester.enterText(editable.first, text);
    await tester.pump();
  }

  /// The macOS menu bar (`PlatformMenuBar`) and its items, as AppKit sees
  /// them. Selecting one runs it exactly as clicking it in the menu bar
  /// does.
  List<PlatformMenuItem> get _menuItems {
    final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
    final items = <PlatformMenuItem>[];
    void walk(List<PlatformMenuItem> list) {
      for (final entry in list) {
        switch (entry) {
          case PlatformMenu(:final menus):
            walk(menus);
          case PlatformMenuItemGroup(:final members):
            walk(members);
          default:
            items.add(entry);
        }
      }
    }

    walk(bar.menus);
    return items;
  }

  /// Chooses [label] in the menu bar, e.g. Vault › Lock.
  Future<void> menu(String label) async {
    final item = _menuItems.firstWhere((i) => i.label == label);
    expect(item.onSelected, isNotNull, reason: 'menu item $label is disabled');
    item.onSelected!();
    await settle();
  }

  /// Presses ⌘[key]. On macOS the menu bar owns these keys (AppKit matches
  /// the key equivalent and selects the menu item), and a synthesized key
  /// event never reaches AppKit, so this does what AppKit would: finds the
  /// item with that shortcut and selects it.
  Future<void> command(LogicalKeyboardKey key) async {
    final item = _menuItems.firstWhere((i) {
      final s = i.shortcut;
      return s is SingleActivator &&
          s.trigger == key &&
          s.meta &&
          !s.shift &&
          !s.control;
    });
    expect(item.onSelected, isNotNull, reason: '⌘${key.keyLabel} disabled');
    item.onSelected!();
    await settle();
  }

  /// Picks [label] from a pop-up button's menu, as the user would.
  Future<void> choose(Finder popup, String label) async {
    await tap(popup);
    final option = find.text(label).last;
    await tap(option);
  }

  Finder inSheet(Finder f) =>
      find.descendant(of: find.byType(ImportDialog), matching: f);

  Finder inSidebar(Finder f) =>
      find.descendant(of: find.byType(VaultSidebar), matching: f);

  Finder sidebarRow(String label) =>
      inSidebar(find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}')));

  Finder listed(String title) => find.descendant(
    of: find.byType(VaultListPane),
    matching: find.text(title),
  );

  Finder inInspector(Finder f) =>
      find.descendant(of: find.byType(DesktopInspector), matching: f);

  Finder inStatusBar(String text) => find.descendant(
    of: find.byType(ShellStatusBar),
    matching: find.text(text),
  );

  Finder formField(String label) => find.descendant(
    of: find.ancestor(
      of: find.text('$label:'),
      matching: find.byType(DesktopFormRow),
    ),
    matching: find.byType(EditableText),
  );

  Finder button(String label) =>
      find.widgetWithText(DesktopButton, label).hitTestable();

  /// The text of every toast on screen (desktop banners).
  List<String> toastTexts() {
    final cards = find.byWidgetPredicate(
      (w) => const {
        '_BCToastCard',
        '_Toast',
        'InfoBar',
      }.contains(w.runtimeType.toString()),
    );
    return [
      for (final text in tester.widgetList<RichText>(
        find.descendant(of: cards, matching: find.byType(RichText)),
      ))
        text.text.toPlainText(),
    ];
  }

  void expectNoSecretInToasts(Iterable<String> secrets) {
    final texts = toastTexts();
    expect(texts, isNotEmpty, reason: 'no toast is showing');
    for (final secret in secrets) {
      for (final text in texts) {
        expect(text.contains(secret), isFalse, reason: 'toast shows "$text"');
      }
    }
  }

  Future<String?> clipboard() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  Future<void> unlock(String with_) async {
    expect(find.text('Unlock your vault'), findsOneWidget);
    await type(find.byType(EditableText).first, with_);
    await tap(find.bySemanticsLabel('Unlock'));
    await until(
      () =>
          session is Unlocked ||
          find.textContaining("didn't open").evaluate().isNotEmpty,
      what: 'unlock',
    );
    await settle();
  }

  /// A parser fixture (packages/cred_parsers/test/fixtures): the sandboxed
  /// app can't read the source tree, so the bytes are compiled in.
  Uint8List fixture(String name) => walkthroughFixture(name);

  // -------------------------------------------------------------------------
  // The flows on the card, in the order a new user meets them.
  // -------------------------------------------------------------------------

  Future<void> run() async {
    await step('1 · Create a vault', _create);
    await step('1b · Recovery kit', _recoveryKit);
    await step('2 · Lock and unlock', _lockUnlock);
    await step('3 · Import every type (D04)', _importAll);
    await step('3b · New items with your own expiry', _newItems);
    await step('4 · Inspector: fields, reveal, export', _inspector);
    await step('4b · Copy a secret: clipboard guard', _clipboard);
    await step('5 · Search: toolbar field', _search);
    await step('5b · Quick open (⌘K)', _quickOpen);
    await step('6 · Expiry dashboard', _expiry);
    await step('7a · Settings › General: reminders', _reminders);
    await step('7b · Settings › Security: auto-lock', _autoLock);
    await step('7c · Settings › Security: change password', _changePassword);
    await step('7d · Settings › Security: new recovery kit', _newKit);
    await step('7e · Settings › Security: rotate key', _rotate);
    await step('7f · Settings › Sync (local folder)', _sync);
    await step('7g · Pair a device', _pairing);
    await step('7h · Settings › AI Agents', _agents);
    await step('8a · Explorer: new organization and app', _explorerNew);
    await step('8b · Explorer: drag an item onto an app', _explorerDrag);
    await step('8c · Explorer: keyboard and context menus', _explorerKeys);
    await step('9 · Lock at the end', _finalLock);
  }

  // 1 ----------------------------------------------------------------------

  Future<void> _create() async {
    // A fresh device opens on Create (N01).
    await until(
      () => find.text('Create a master password').evaluate().isNotEmpty,
      what: 'the create screen',
    );
    expect(location, Routes.create);
    expect(find.text('Step 1 of 3'), findsOneWidget);
    await shot('create-empty');

    // A short password is refused before anything is made.
    await type(find.byType(EditableText).at(0), 'abc');
    await tap(button('Continue'));
    expect(find.text('Use at least 4 characters'), findsOneWidget);
    // A typo in the confirmation too.
    await type(find.byType(EditableText).at(0), _password);
    await type(find.byType(EditableText).at(1), '${_password}x');
    await tap(button('Continue'));
    expect(find.text("The passwords don't match"), findsOneWidget);
    expect(session, isA<NoVault>());

    await type(find.byType(EditableText).at(1), _password);
    expect(find.text('Strong'), findsOneWidget);
    await shot('create-filled');
    await tap(button('Continue'));
    await until(
      () => container.read(pendingRecoveryKeyProvider) != null,
      what: 'Argon2id and the new vault',
    );
    await settle();
    expect(session, isA<Unlocked>());
    expect(location, Routes.createRecoveryKit);
  }

  Future<void> _recoveryKit() async {
    expect(find.text('Save your recovery key'), findsOneWidget);
    expect(find.text('Step 2 of 3'), findsOneWidget);
    final key = container.read(pendingRecoveryKeyProvider)!.toDisplayString();
    // The vault stays closed until the user says the key is saved.
    expect(
      tester.widget<DesktopButton>(button('Open Vault')).onPressed,
      isNull,
    );
    await shot('recovery-kit');

    await tap(button('Save as Text…'));
    await until(
      () => saver.saved.keys.any((n) => n.endsWith('.txt')),
      what: 'the kit to be saved',
    );
    final text = String.fromCharCodes(
      saver.saved.entries.firstWhere((e) => e.key.endsWith('.txt')).value,
    );
    expect(text, contains(key));
    expect(text, contains((session as Unlocked).vault.vaultId));
    expect(find.text('Recovery kit saved'), findsOneWidget);
    expectNoSecretInToasts([key]);
    await shot('recovery-kit-saved');

    await tapText("I've saved my recovery key somewhere safe");
    await tap(button('Open Vault'));
    await until(
      () => find.byType(VaultListPane).evaluate().isNotEmpty,
      what: 'the vault window',
    );
    expect(container.read(pendingRecoveryKeyProvider), isNull);
    expect(find.text('Your vault is empty'), findsOneWidget);
    await shot('vault-empty');
  }

  // 2 ----------------------------------------------------------------------

  Future<void> _lockUnlock() async {
    // Vault › Lock (⌘L) from the menu bar.
    await command(LogicalKeyboardKey.keyL);
    await until(() => session is Locked, what: 'the lock');
    await settle();
    expect(find.text('Unlock your vault'), findsOneWidget);
    await shot('unlock');

    await type(find.byType(EditableText).first, _wrongPassword);
    await submit();
    await until(
      () => find
          .text("That password didn't open this vault")
          .evaluate()
          .isNotEmpty,
      what: 'the wrong-password error',
    );
    expect(session, isA<Locked>());
    // The field is cleared for another try.
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .controller
          .text,
      isEmpty,
    );
    await shot('unlock-wrong-password');

    await unlock(password);
    expect(session, isA<Unlocked>());
    expect(find.byType(VaultListPane), findsOneWidget);
  }

  // 3 ----------------------------------------------------------------------

  Future<void> _importAll() async {
    final parsers = CredentialParsers.standard();
    final coveredByToast = <String>[];
    for (final (i, c) in _imports.indexed) {
      final bytes = fixture(c.file);
      final before = index.all.length;
      opener.queue.add([PickedFile(name: c.file, bytes: bytes)]);
      // Alternate the toolbar button and File › Import… (⌘I).
      if (i.isEven) {
        await tap(
          find.descendant(
            of: find.byType(ShellToolbar),
            matching: find.bySemanticsLabel(RegExp('^Import a file')),
          ),
        );
      } else {
        await command(LogicalKeyboardKey.keyI);
      }
      await until(
        () =>
            find.byType(ImportDialog).evaluate().isNotEmpty &&
            inSheet(find.bySemanticsLabel('Reading the file'))
                .evaluate()
                .isEmpty,
        what: 'the import sheet for ${c.file}',
      );
      await settle();
      expect(find.text('Import ${c.file}'), findsOneWidget);

      // Passwords first, as the sheet asks for them.
      var result = parsers.parse(ParseInput(filename: c.file, bytes: bytes));
      if (c.secrets.isNotEmpty) {
        await shot('import-${_slug(c.file)}-password');
        for (final MapEntry(:key, :value) in c.secrets.entries) {
          await type(find.byKey(ValueKey('import-secret-$key')), value);
        }
        await tap(button('Unlock file'));
        await until(
          () => inSheet(find.text('Details')).evaluate().isNotEmpty,
          what: '${c.file} to open',
        );
        result = parsers.parse(
          ParseInput(filename: c.file, bytes: bytes, secrets: c.secrets),
        );
      }
      expect(result.type, c.type, reason: c.file);

      // Every fact the file holds is shown, from the file.
      for (final MapEntry(:value) in result.facts.entries) {
        if (value.secret) continue;
        expect(
          inSheet(find.text(value.value)),
          findsWidgets,
          reason: '${c.file}: fact "${value.value}" not shown',
        );
      }
      final expires = result.expiresAt;
      if (expires != null) {
        expect(
          inSheet(
            find.text(
              'Expires ${DateFormat.yMMMd().add_Hm().format(expires.toLocal())}',
            ),
          ),
          findsOneWidget,
          reason: c.file,
        );
      } else {
        expect(
          inSheet(find.textContaining('No expiry date in the file')),
          findsOneWidget,
          reason: c.file,
        );
      }
      for (final text in c.shows) {
        expect(inSheet(find.text(text)), findsWidgets, reason: text);
      }
      for (final MapEntry(:key, :value) in c.required.entries) {
        await type(find.byKey(ValueKey('import-field-$key')), value);
      }
      // WALK-04: the expiry line (what the file says about expiry) is in
      // view without scrolling at the window's default size, and so is
      // the Keep-password checkbox; a long details box scrolls on its own.
      final expiryLine = inSheet(
        expires == null
            ? find.textContaining('No expiry date in the file')
            : find.textContaining('Expires '),
      );
      expect(
        expiryLine.hitTestable(),
        findsOneWidget,
        reason: 'WALK-04: ${c.file}: the expiry line is out of view',
      );
      if (c.secrets.isNotEmpty) {
        expect(
          inSheet(find.text('Keep the password with the item')).hitTestable(),
          findsOneWidget,
          reason:
              'WALK-04: ${c.file}: the Keep-password checkbox is out '
              'of view',
        );
      }
      await shot('import-${_slug(c.file)}');

      await tap(inSheet(button('Add to Vault')));
      await until(
        () =>
            index.all.length == before + 1 &&
            find.byType(ImportDialog).evaluate().isEmpty,
        what: '${c.file} to land in the vault',
      );
      await settle(const Duration(seconds: 1));
      final added = index.all.firstWhere(
        (it) => it.attachments.any((a) => a.filename == c.file),
      );
      expect(added.typeName, c.type.wireName, reason: c.file);
      expect(added.expiresAt, result.expiresAt, reason: c.file);
      expect(
        added.expiresSource,
        result.expiresAt == null ? null : ExpirySource.file,
      );
      expect(router.state.uri.queryParameters['item'], added.id);
      expect(listed(added.title), findsWidgets, reason: c.file);
      if (c.secrets.isNotEmpty) {
        expectNoSecretInToasts(c.secrets.values);
      }
      // The "File imported" toast sits over the inspector's header.
      final edit = inInspector(find.widgetWithText(DesktopButton, 'Edit'));
      if (edit.evaluate().isNotEmpty &&
          edit.hitTestable().evaluate().isEmpty &&
          toastTexts().isNotEmpty) {
        coveredByToast.add(c.file);
      }
    }
    // KNOWN ISSUE WALK-05 (should fix): the toast after an import covers
    // the inspector's Export / Edit / ⋯ buttons while it shows.
    knownIssue(
      'WALK-05',
      coveredByToast.isEmpty,
      'the inspector\'s Edit button can be clicked right after an import '
          '(covered by the toast after: ${coveredByToast.join(', ')})',
    );

    // A file nothing reads is kept as a generic file, with nothing made up.
    final before = index.all.length;
    final notes = Uint8List.fromList(
      'walkthrough notes, not a key\n'.codeUnits,
    );
    opener.queue.add([PickedFile(name: 'walkthrough-notes.txt', bytes: notes)]);
    await command(LogicalKeyboardKey.keyI);
    await until(
      () => inSheet(button('Add to Vault')).evaluate().isNotEmpty,
      what: 'the generic file sheet',
    );
    expect(inSheet(find.text('Details')), findsNothing);
    expect(inSheet(find.textContaining('Generic File')), findsWidgets);
    await shot('import-generic-file');
    await tap(inSheet(button('Add to Vault')));
    await until(() => index.all.length == before + 1, what: 'the generic file');
    expect(
      index.all.last.typeName == ItemType.genericFile.wireName ||
          index.all.any(
            (i) =>
                i.typeName == ItemType.genericFile.wireName &&
                i.attachments.single.filename == 'walkthrough-notes.txt',
          ),
      isTrue,
    );

    // The same file again offers the one already there.
    opener.queue.add([
      PickedFile(
        name: 'google-services.json',
        bytes: fixture('google-services.json'),
      ),
    ]);
    await command(LogicalKeyboardKey.keyI);
    await until(
      () => find.textContaining('already in your vault').evaluate().isNotEmpty,
      what: 'the duplicate notice',
    );
    await shot('import-duplicate');
    await tap(inSheet(button('Open existing')));
    expect(find.byType(ImportDialog), findsNothing);
    expect(index.all.length, before + 1);
    await shot('vault-after-imports');
  }

  Future<void> _newItems() async {
    final today = DateTime.now();
    String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
    for (final (title, value, date) in [
      (
        'Walkthrough token (soon)',
        _soonToken,
        today.add(const Duration(days: 10)),
      ),
      (
        'Walkthrough token (expired)',
        _expiredToken,
        today.subtract(const Duration(days: 3)),
      ),
    ]) {
      // File › New Item (⌘N).
      await command(LogicalKeyboardKey.keyN);
      expect(find.text('New item'), findsWidgets);
      await type(find.byKey(const ValueKey('item-name')), title);
      await type(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Value value',
        ),
        value,
      );
      await type(find.byKey(const ValueKey('item-expiry')), ymd(date));
      await shot('new-item-${_slug(title)}');
      await tap(button('Add item'));
      await until(
        () => index.all.any((i) => i.title == title),
        what: '$title to be saved',
      );
      await settle();
      final saved = item(title);
      expect(saved.typeName, ItemType.genericSecret.wireName);
      expect(saved.expiresSource, ExpirySource.user);
      expect(saved.fields['value']!.secret, isTrue);
      expect(find.text(value), findsNothing, reason: 'shown masked');
    }
    await shot('new-items');
  }

  // 4 ----------------------------------------------------------------------

  Future<void> _inspector() async {
    final keystore = index.all.firstWhere(
      (i) => i.typeName == ItemType.androidKeystore.wireName,
    );
    await tap(listed(keystore.title));
    expect(router.state.uri.queryParameters['item'], keystore.id);
    expect(inInspector(find.text(keystore.title)), findsWidgets);
    expect(inInspector(find.text('Fields')), findsOneWidget);
    expect(inInspector(find.text('test.jks')), findsOneWidget);
    expect(inInspector(find.text('Save As…')), findsOneWidget);
    // Expiry box: from the file.
    expect(inInspector(find.text('From file')), findsOneWidget);
    // The store password the user typed is kept as a masked secret.
    expect(find.bySemanticsLabel('Store password, hidden'), findsOneWidget);
    expect(find.text(_fixturePassword), findsNothing);
    await shot('inspector-keystore');

    await tap(iconButton('Reveal Store password'));
    expect(inInspector(find.text(_fixturePassword)), findsOneWidget);
    await shot('inspector-revealed');
    await tap(iconButton('Hide Store password'));
    expect(find.text(_fixturePassword), findsNothing);

    // Status bar: the item's history.
    expect(
      find.descendant(
        of: find.byType(ShellStatusBar),
        matching: find.textContaining('Created'),
      ),
      findsWidgets,
    );

    // Save As… writes the file back byte for byte.
    await tap(inInspector(find.text('Save As…')));
    await until(() => saver.saved.containsKey('test.jks'), what: 'export');
    expect(saver.saved['test.jks'], fixture('test.jks'));
    await shot('inspector-exported');
  }

  Future<void> _clipboard() async {
    // Settings › Security: clear copied secrets after 10 seconds (the
    // shortest choice).
    await menu('Settings…');
    await tap(find.bySemanticsLabel('Security'));
    expect(location, Routes.settingsSecurity);
    await choose(find.byType(DesktopPopup<Duration>), '10 seconds');
    expect(
      container.read(settingsProvider).clipboardClearAfter,
      const Duration(seconds: 10),
    );
    await shot('settings-security-clipboard-10s');

    final token = item('Walkthrough token (soon)');
    router.go(Routes.vault(item: token.id));
    await settle();
    final guard = container.read(clipboardGuardProvider);
    await tap(iconButton('Copy Value'));
    await until(() => guard.isHoldingSecret, what: 'the copy');
    expect(await clipboard(), _soonToken);
    expect(find.text('Value copied'), findsOneWidget);
    expect(
      find.text('Clears from the clipboard in 10 seconds.'),
      findsOneWidget,
    );
    expectNoSecretInToasts([_soonToken]);
    expect(find.text(_soonToken), findsNothing, reason: 'copy never reveals');
    await shot('inspector-copied');

    // After 10 s the clipboard is empty again.
    final copiedAt = DateTime.now();
    await until(
      () => !guard.isHoldingSecret,
      within: const Duration(seconds: 15),
      what: 'the guard to clear the clipboard',
    );
    final took = DateTime.now().difference(copiedAt);
    expect(took, greaterThan(const Duration(seconds: 8)));
    expect(await clipboard(), anyOf(isNull, isEmpty));
    note('cleared after ${took.inMilliseconds} ms');

    // Something the user copied since is left alone.
    await tap(iconButton('Copy Value'));
    await until(() => guard.isHoldingSecret, what: 'the second copy');
    await Clipboard.setData(const ClipboardData(text: 'walkthrough: mine'));
    await until(
      () => !guard.isHoldingSecret,
      within: const Duration(seconds: 15),
      what: 'the guard to give up',
    );
    expect(await clipboard(), 'walkthrough: mine');
    await Clipboard.setData(const ClipboardData(text: ''));
  }

  // 5 ----------------------------------------------------------------------

  Future<void> _search() async {
    router.go(Routes.vault());
    await settle();
    // Edit › Find (⌘F) focuses the toolbar's search field.
    await command(LogicalKeyboardKey.keyF);
    final field = find.descendant(
      of: find.byType(ShellToolbar),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);

    final authKey = index.all.firstWhere(
      (i) => i.typeName == ItemType.appleAuthKey.wireName,
    );
    final firebase = index.all.firstWhere(
      (i) => i.attachments.any((a) => a.filename == 'google-services.json'),
    );
    for (final (query, expected, label) in [
      ('Walkthrough token', 'Walkthrough token (soon)', 'title'),
      ('TESTKEY123', authKey.title, 'key ID'),
      ('google-services.json', firebase.title, 'file name'),
    ]) {
      await type(field, query);
      await settle();
      expect(VaultFilterQuery.of(location), query);
      expect(
        listed(expected),
        findsWidgets,
        reason: 'searching by $label ("$query") finds "$expected"',
      );
      await shot('search-${_slug(label)}');
    }
    // Secrets are never found.
    await type(field, _soonToken);
    await settle();
    expect(listed('Walkthrough token (soon)'), findsNothing);
    await shot('search-secret-not-found');
    await type(field, '');
    await settle();
  }

  Future<void> _quickOpen() async {
    // View › Quick Open (⌘K).
    await command(LogicalKeyboardKey.keyK);
    expect(find.byType(QuickOpen), findsOneWidget);
    expect(find.text('Recently changed'), findsOneWidget);
    await shot('quick-open');
    final input = find.descendant(
      of: find.byType(QuickOpen),
      matching: find.byType(EditableText),
    );
    final authKey = index.all.firstWhere(
      (i) => i.typeName == ItemType.appleAuthKey.wireName,
    );
    for (final query in ['TESTKEY123', 'id_ed25519', 'walkthrough token']) {
      await type(input, query);
      await settle();
      expect(find.text('No matches'), findsNothing, reason: query);
      await shot('quick-open-${_slug(query)}');
    }
    await type(input, _expiredToken);
    await settle();
    expect(find.text('No matches'), findsOneWidget);
    await type(input, 'TESTKEY123');
    await settle();
    await press(LogicalKeyboardKey.enter);
    expect(find.byType(QuickOpen), findsNothing);
    expect(router.state.uri.queryParameters['item'], authKey.id);
    // Escape closes it without opening anything.
    await command(LogicalKeyboardKey.keyK);
    await press(LogicalKeyboardKey.escape);
    expect(find.byType(QuickOpen), findsNothing);
  }

  // 6 ----------------------------------------------------------------------

  Future<void> _expiry() async {
    // Vault › Expiry.
    await menu('Expiry');
    expect(location, Routes.expiry);
    expect(find.byType(ExpiryScreen), findsOneWidget);
    final all = index.all;
    final dated = all.where((i) => i.expiresAt != null).toList();
    final expired = dated.where((i) => i.expiresAt!.isBefore(now())).length;
    final soon = dated
        .where(
          (i) =>
              !i.expiresAt!.isBefore(now()) &&
              i.expiresAt!.isBefore(now().add(const Duration(days: 31))),
        )
        .length;
    expect(find.text('Expired · $expired'), findsOneWidget);
    expect(find.text('Within 30 days · $soon'), findsOneWidget);
    expect(
      find.text('Later · ${dated.length - expired - soon}'),
      findsOneWidget,
    );
    expect(find.text('Set by you'), findsWidgets);
    expect(find.text('From file'), findsWidgets);
    expect(
      inStatusBar(
        '${dated.length} dated · ${all.length - dated.length} '
        'without a date',
      ),
      findsOneWidget,
    );
    expect(inStatusBar('Reminders on · at most two per item'), findsOneWidget);
    await shot('expiry');

    // The sidebar's Expired list shows the dashboard, expired only.
    await tap(sidebarRow('Expired'));
    await shot('expiry-sidebar-expired');
    expect(location, Routes.expiryShowing(expired: true));
    expect(find.text('Walkthrough token (expired)'), findsWidgets);
    expect(find.text('Walkthrough token (soon)'), findsNothing);
    expect(inStatusBar('1 expired'), findsOneWidget);
    // KNOWN ISSUE WALK-03 (nice to have): an item that expired on a date
    // three days back says "4 days ago": the Left column rounds the time
    // since up, as it does the time left.
    final expiredLeft = DesktopExpiryTable.left(
      item('Walkthrough token (expired)').expiresAt!,
      now(),
    );
    expect(find.text(expiredLeft), findsWidgets);
    knownIssue(
      'WALK-03',
      expiredLeft == '3 days ago',
      'an expiry 3 calendar days ago reads "3 days ago" (reads '
          '"$expiredLeft")',
    );

    // "Expiring in 30 days" counts one item.
    await tap(sidebarRow('Expiring in 30 days'));
    await shot('sidebar-expiring');
    // As in N06, it opens the dashboard with every group.
    expect(location, Routes.expiry);
    expect(find.text('Within 30 days · 1'), findsOneWidget);

    // A row on the dashboard opens the item.
    await menu('Expiry');
    await tap(find.text('Walkthrough token (soon)').last);
    expect(
      router.state.uri.queryParameters['item'],
      item('Walkthrough token (soon)').id,
    );
  }

  // 7 ----------------------------------------------------------------------

  Future<void> _reminders() async {
    // Reminders were planned for the dated items (fake notification
    // centre: nothing is posted on this Mac).
    await until(
      () => alerts.scheduled.isNotEmpty,
      what: 'reminders to be scheduled',
    );
    expect(alerts.permissionAsks, 1);
    final soon = item('Walkthrough token (soon)');
    final forSoon = alerts.scheduled.where((a) => a.itemId == soon.id).toList();
    expect(forSoon, isNotEmpty);
    for (final alert in forSoon) {
      expect(alert.fireAt.hour, 9);
      expect(alert.title.contains(_soonToken), isFalse);
      expect(alert.body.contains(_soonToken), isFalse);
    }
    note('${alerts.scheduled.length} reminders scheduled');

    await menu('Settings…');
    await tap(find.bySemanticsLabel('General'));
    expect(location, Routes.settings);
    expect(find.text('Expiry reminders'), findsOneWidget);
    await shot('settings-general');
    final cancelledBefore = alerts.cancelled.length;
    await tap(find.text('Expiry reminders'));
    expect(container.read(settingsProvider).expiryReminders, isFalse);
    await until(
      () => alerts.cancelled.length > cancelledBefore,
      what: 'reminders to be withdrawn',
    );
    await shot('settings-general-reminders-off');
    await menu('Expiry');
    expect(inStatusBar('Reminders off'), findsOneWidget);
    await menu('Settings…');
    await tap(find.bySemanticsLabel('General'));
    await tap(find.text('Expiry reminders'));
    expect(container.read(settingsProvider).expiryReminders, isTrue);

    // Settings are saved in the test's folder only.
    await until(
      () => File('${support.path}/settings.json').existsSync(),
      what: 'settings.json',
    );
  }

  Future<void> _autoLock() async {
    await tap(find.bySemanticsLabel('Security'));
    expect(find.textContaining('⌘L locks right away'), findsOneWidget);
    await choose(find.byType(DesktopPopup<int>), '1 minute');
    expect(
      container.read(settingsProvider).autoLockAfter,
      const Duration(minutes: 1),
    );
    await shot('settings-security-lock-1min');
    router.go(Routes.vault());
    await settle();
    expect(inSidebar(find.text('1m')), findsOneWidget);
    await shot('vault-footer-autolock');

    // Idle time is read from the wall clock every 5 s: move the clock past
    // a minute of no input (as a Mac waking from sleep would) and wait for
    // the next check.
    skew += const Duration(minutes: 1, seconds: 2);
    await until(
      () => session is Locked,
      within: const Duration(seconds: 12),
      what: 'the idle lock',
    );
    await settle();
    expect(find.text('Unlock your vault'), findsOneWidget);
    expect(container.read(clipboardGuardProvider).isHoldingSecret, isFalse);
    await shot('auto-locked');
    await unlock(password);
    expect(session, isA<Unlocked>());

    // Back to five minutes, so the rest of the walk isn't interrupted.
    container
        .read(settingsProvider.notifier)
        .setAutoLock(const Duration(minutes: 5));
    await settle();
  }

  Future<void> _changePassword() async {
    await menu('Settings…');
    await tap(find.bySemanticsLabel('Security'));
    await tap(button('Change…'));
    await type(formField('Current password'), _wrongPassword);
    await type(formField('New password'), _newPassword);
    await type(formField('Confirm new password'), _newPassword);
    await tapText('Change Password');
    await until(
      () => find.text("That isn't your current password").evaluate().isNotEmpty,
      what: 'the wrong-password error',
    );
    await shot('change-password-wrong');
    await type(formField('Current password'), password);
    await tapText('Change Password');
    await until(
      () => find.text('Master password changed').evaluate().isNotEmpty,
      what: 'the change',
    );
    expectNoSecretInToasts([password, _newPassword]);
    await shot('change-password-done');
    final old = password;
    password = _newPassword;

    await command(LogicalKeyboardKey.keyL);
    await until(() => session is Locked, what: 'the lock');
    await settle();
    await type(find.byType(EditableText).first, old);
    await tap(find.bySemanticsLabel('Unlock'));
    await until(
      () => find.textContaining("didn't open").evaluate().isNotEmpty,
      what: 'the old password to be refused',
    );
    await unlock(password);
    expect(session, isA<Unlocked>());
  }

  Future<void> _newKit() async {
    await menu('Settings…');
    await tap(find.bySemanticsLabel('Security'));
    final vault = (session as Unlocked).vault;
    expect(find.text(vault.vaultId), findsOneWidget);
    await tap(button('Show in Finder'));
    expect(revealer.revealed, [vault.store.root.path]);

    await tap(button('New Kit…'));
    expect(find.text('New recovery kit'), findsOneWidget);
    await type(
      find.descendant(
        of: find.byType(NewRecoveryKitDialog),
        matching: find.byType(EditableText),
      ),
      password,
    );
    await tap(button('Make New Key'));
    await until(
      () => find.byType(RecoveryKitCard).evaluate().isNotEmpty,
      what: 'the new key',
    );
    await settle();
    final key = tester
        .widget<RecoveryKitCard>(find.byType(RecoveryKitCard))
        .kit
        .recoveryKey;
    await shot('new-recovery-kit');
    // KNOWN ISSUE WALK-06 (should fix): the sheet shows the phone's
    // recovery-kit card (bc_ui pill buttons "Save PDF", "Save as text")
    // instead of N02's desktop push buttons.
    knownIssue(
      'WALK-06',
      find
          .descendant(
            of: find.byType(NewRecoveryKitDialog),
            matching: find.widgetWithText(DesktopButton, 'Save PDF…'),
          )
          .evaluate()
          .isNotEmpty,
      'Settings › New Kit… shows the key with the desktop (N02) buttons',
    );

    // Copy goes through the guard; the toast should say when it clears.
    await tap(
      find.descendant(
        of: find.byType(NewRecoveryKitDialog),
        matching: find.text('Copy'),
      ),
    );
    await until(
      () => find.text('Recovery key copied').evaluate().isNotEmpty,
      what: 'the copy toast',
    );
    expect(await clipboard(), key);
    expectNoSecretInToasts([key]);
    await shot('new-recovery-kit-copied');
    final after = container.read(settingsProvider).clipboardClearAfter;
    // KNOWN ISSUE WALK-01 (should fix): the toast says "30 seconds"
    // whatever the setting (recovery_kit_card.dart), here 10.
    knownIssue(
      'WALK-01',
      find
          .text('It clears from the clipboard in ${after.inSeconds} seconds.')
          .evaluate()
          .isNotEmpty,
      'the recovery-key copy toast says the clipboard clears in '
          '${after.inSeconds} seconds (the setting), not a fixed 30',
    );
    await container.read(clipboardGuardProvider).clearNow();
    expect(await clipboard(), anyOf(isNull, isEmpty));

    await tapText("I've saved the new key");
    await tap(
      find.descendant(
        of: find.byType(NewRecoveryKitDialog),
        matching: find.widgetWithText(DesktopButton, 'Done'),
      ),
    );
    expect(find.byType(NewRecoveryKitDialog), findsNothing);
  }

  Future<void> _rotate() async {
    final before = session as Unlocked;
    final oldVkId = before.vault.header.vkId;
    final titles = before.index.all.map((i) => i.title).toSet();
    await tap(button('Rotate…'));
    expect(find.text('Rotate vault key'), findsOneWidget);
    await shot('rotate-key');
    await type(
      find.descendant(
        of: find.byType(NewRecoveryKitDialog),
        matching: find.byType(EditableText),
      ),
      password,
    );
    await tap(button('Rotate Key'));
    await until(
      () => find.byType(RecoveryKitCard).evaluate().isNotEmpty,
      within: const Duration(seconds: 60),
      what: 'the rotation',
    );
    await settle();
    expect(find.text('Your new recovery key'), findsOneWidget);
    await shot('rotate-key-done');
    await tapText("I've saved the new key");
    await tap(
      find.descendant(
        of: find.byType(NewRecoveryKitDialog),
        matching: find.widgetWithText(DesktopButton, 'Done'),
      ),
    );
    final after = session as Unlocked;
    expect(after.vault.header.vkId, isNot(oldVkId));
    expect(after.index.all.map((i) => i.title).toSet(), titles);

    // Unlocking afterwards still works with the master password, and every
    // file still opens.
    await command(LogicalKeyboardKey.keyL);
    await until(() => session is Locked, what: 'the lock');
    await settle();
    await unlock(password);
    final reopened = session as Unlocked;
    expect(reopened.vault.header.vkId, after.vault.header.vkId);
    expect(reopened.index.all.map((i) => i.title).toSet(), titles);
    for (final it in reopened.index.all) {
      for (final a in it.attachments) {
        expect(await reopened.vault.readAttachment(a), isNotNull);
      }
    }
    await shot('after-rotation-unlocked');
  }

  Future<void> _sync() async {
    await menu('Settings…');
    await tap(find.bySemanticsLabel('Sync'));
    expect(location, Routes.settingsSync);
    expect(find.text('Turn on sync first.'), findsOneWidget);
    await shot('settings-sync-empty');
    // R2 is preselected. These values are made up: the storage is a local
    // folder (LocalDirBackend), so no request leaves the Mac.
    await type(formField('Account ID'), '0123456789abcdef0123456789abcdef');
    await type(formField('Bucket'), 'walkthrough-bucket');
    await type(formField('Folder'), 'devvault');
    await type(formField('Access key ID'), 'AKIA-WALKTHROUGH-FAKE');
    await type(formField('Secret access key'), 'fake-walkthrough-secret-key');
    await tap(button('Test Connection'));
    await until(
      () => find
          .text('Connected · conditional writes enforced')
          .evaluate()
          .isNotEmpty,
      what: 'the connection test',
    );
    await shot('settings-sync-tested');
    await tap(button('Turn On Sync'));
    await until(
      () => container.read(syncSetupProvider) != null,
      what: 'sync to turn on',
    );
    await until(
      () =>
          container.read(syncControllerProvider) is! SyncRunning &&
          bucket.listSync(recursive: true).whereType<File>().isNotEmpty,
      within: const Duration(seconds: 30),
      what: 'the first sync',
    );
    await settle();
    expect(
      find.textContaining('Cloudflare R2 · walkthrough-bucket'),
      findsWidgets,
    );
    // The keys went to the (fake) keychain, not to settings or the vault.
    expect(
      keychain.values.values.any(
        (v) => v.contains('fake-walkthrough-secret-key'),
      ),
      isTrue,
    );
    final settingsText = File('${support.path}/settings.json')
        .readAsStringSync();
    expect(settingsText.contains('fake-walkthrough-secret-key'), isFalse);
    final objects = bucket.listSync(recursive: true).whereType<File>().length;
    note('$objects objects in the local bucket');
    await shot('settings-sync-on');
    // Vault › Sync Now (⌘R) is enabled now, and runs.
    await command(LogicalKeyboardKey.keyR);
    await until(
      () => container.read(syncControllerProvider) is! SyncRunning,
      within: const Duration(seconds: 30),
      what: 'Sync Now',
    );
  }

  Future<void> _pairing() async {
    if (!location.startsWith(Routes.settingsSync)) {
      await menu('Settings…');
      await tap(find.bySemanticsLabel('Sync'));
    }
    await tap(button('Pair…'));
    await until(
      () => find.byType(QrImageView).evaluate().isNotEmpty,
      what: 'the pairing QR',
    );
    await settle(const Duration(seconds: 1));
    expect(find.text('Pair a device'), findsWidgets);
    expect(find.textContaining(', then the code expires'), findsOneWidget);
    final code = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere(RegExp(r'^[0-9A-Z]{4}-[0-9A-Z]{4}$').hasMatch);
    await shot('pair-device');
    // The QR and code are only shown; no device is paired.
    expect(code, hasLength(9));
    await tap(button('Done'));
    expect(find.byType(PairScreen), findsNothing);
  }

  Future<void> _agents() async {
    if (!location.startsWith(Routes.settings)) await menu('Settings…');
    await tap(find.bySemanticsLabel('AI Agents'));
    expect(location, Routes.settingsAgents);
    expect(find.text('Allow AI agents'), findsOneWidget);
    expect(find.text('Set up an agent'), findsOneWidget);
    expect(
      find.textContaining('claude mcp add --scope user devvault'),
      findsOneWidget,
    );
    expect(find.text('None yet'), findsOneWidget);
    await shot('settings-agents');
    // Turn agents on: the bridge listens on the test's own socket, then
    // stops again.
    final socket = File(container.read(agentSocketPathProvider)!);
    await tap(find.text('Allow AI agents'));
    expect(container.read(settingsProvider).agentsEnabled, isTrue);
    await until(
      () =>
          FileSystemEntity.typeSync(socket.path) !=
          FileSystemEntityType.notFound,
      what: 'the agent socket',
    );
    expect(container.read(agentBridgeProvider).clients, isEmpty);
    await shot('settings-agents-on');
    await tap(find.text('Allow AI agents'));
    expect(container.read(settingsProvider).agentsEnabled, isFalse);
    await until(
      () =>
          FileSystemEntity.typeSync(socket.path) ==
          FileSystemEntityType.notFound,
      what: 'the agent socket to close',
    );
  }

  // 8 ----------------------------------------------------------------------

  Future<void> _explorerNew() async {
    router.go(Routes.vault());
    await settle();
    await shot('explorer');
    await rightClick(inSidebar(find.text('Apps')));
    await shot('explorer-apps-menu');
    expect(find.text('New organization…'), findsOneWidget);
    expect(find.text('New app…'), findsOneWidget);
    await tapText('New organization…');
    await type(find.byKey(const ValueKey('organization-name')), 'Globex Walk');
    await tapText('Create');
    await until(
      () =>
          index.organizationRecords.values.any((o) => o.name == 'Globex Walk'),
      what: 'the organization',
    );
    await settle();
    expect(sidebarRow('Globex Walk, 0 items'), findsOneWidget);

    await rightClick(sidebarRow('Globex Walk'));
    await shot('explorer-organization-menu');
    await tapText('New app…');
    await type(find.byKey(const ValueKey('app-name')), 'Walkthrough App');
    final org = find.byKey(const ValueKey('app-organization'));
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: org, matching: find.byType(EditableText)),
          )
          .controller
          .text,
      'Globex Walk',
    );
    await shot('explorer-new-app');
    await tap(button('Add app'));
    await until(
      () => index.apps.values.any((a) => a.name == 'Walkthrough App'),
      what: 'the app',
    );
    await settle();
    final app = index.apps.values.firstWhere(
      (a) => a.name == 'Walkthrough App',
    );
    expect(app.organization, 'Globex Walk');
    expect(location, Routes.vault(app: app.id));
    await shot('explorer-app-created');
  }

  Future<void> _explorerDrag() async {
    router.go(Routes.vault());
    await settle();
    final app = index.apps.values.firstWhere(
      (a) => a.name == 'Walkthrough App',
    );
    final title = item('Walkthrough token (soon)').title;
    // Open the organization so the app's row is on screen.
    if (sidebarRow('Walkthrough App').evaluate().isEmpty) {
      await tap(sidebarRow('Globex Walk'));
      router.go(Routes.vault());
      await settle();
    }
    expect(sidebarRow('Walkthrough App'), findsOneWidget);

    // A mouse drag from the table onto the app.
    final from = listed(title).first;
    final to = sidebarRow('Walkthrough App');
    final gesture = await tester.startGesture(
      tester.getCenter(from),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(tester.getCenter(to));
    await tester.pump(const Duration(milliseconds: 200));
    await shot('explorer-dragging');
    await gesture.up();
    await until(
      () => item(title).appId == app.id,
      what: 'the drop to move the item',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('“$title” moved to Walkthrough App'), findsOneWidget);
    await shot('explorer-dropped');
    // The toast's Undo puts it back.
    await tap(find.text('Undo'));
    await until(() => item(title).appId == null, what: 'Undo');
    // And again, for the rest of the walk.
    final again = await tester.startGesture(
      tester.getCenter(listed(title).first),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 50));
    await again.moveBy(const Offset(-30, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await again.moveTo(tester.getCenter(sidebarRow('Walkthrough App')));
    await tester.pump(const Duration(milliseconds: 200));
    await again.up();
    await until(() => item(title).appId == app.id, what: 'the second drop');
    await settle();
    expect(sidebarRow('Walkthrough App, 1 item'), findsOneWidget);
  }

  Future<void> _explorerKeys() async {
    final app = index.apps.values.firstWhere(
      (a) => a.name == 'Walkthrough App',
    );
    final title = 'Walkthrough token (soon)';
    // A click puts the cursor on a row; the arrows walk the tree.
    await tap(sidebarRow('Walkthrough App'));
    expect(location, Routes.vault(app: app.id));
    await press(LogicalKeyboardKey.arrowRight);
    expect(inSidebar(find.text(title)), findsOneWidget);
    await press(LogicalKeyboardKey.arrowRight);
    await press(LogicalKeyboardKey.enter);
    expect(router.state.uri.queryParameters['item'], item(title).id);
    await shot('explorer-keyboard-item');
    await press(LogicalKeyboardKey.arrowLeft);
    await press(LogicalKeyboardKey.arrowLeft);
    expect(inSidebar(find.text(title)), findsNothing);
    // F2 edits the app; Escape closes the sheet.
    await press(LogicalKeyboardKey.f2);
    expect(find.text('Edit app'), findsWidgets);
    await shot('explorer-f2-edit-app');
    await tap(button('Cancel'));
    // Shift-F10 opens the row's menu.
    await tap(sidebarRow('Walkthrough App'));
    await press(LogicalKeyboardKey.f10, shift: true);
    expect(find.text('Move to organization…'), findsOneWidget);
    expect(find.text('Remove from Globex Walk'), findsOneWidget);
    await shot('explorer-shift-f10-menu');
    // The menu should take the keyboard: ↓ to its first command, Escape
    // to close it.
    await press(LogicalKeyboardKey.escape);
    final stillOpen = find.text('Move to organization…').evaluate().isNotEmpty;
    // KNOWN ISSUE WALK-02 (should fix): focus stays on the tree, so
    // Escape doesn't close the menu and the arrows move the tree's cursor
    // behind it.
    knownIssue(
      'WALK-02',
      !stillOpen,
      'Escape closes the menu Shift-F10 opened',
    );
    if (stillOpen) {
      final before = location;
      await press(LogicalKeyboardKey.arrowDown);
      await press(LogicalKeyboardKey.enter);
      note(
        'with the menu open, ↓ then Return went to the tree: '
        '$before → $location; menu still open: '
        '${find.text('Move to organization…').evaluate().isNotEmpty}',
      );
      await shot('explorer-menu-after-escape');
      // Close it with a click elsewhere.
      await tester.tapAt(
        tester.getCenter(find.byType(ShellStatusBar)),
        kind: PointerDeviceKind.mouse,
      );
      await settle();
    }
    // Typing jumps to a row by name.
    await tap(sidebarRow('Walkthrough App'));
    await press(LogicalKeyboardKey.home);
    await press(LogicalKeyboardKey.keyN);
    await press(LogicalKeyboardKey.enter);
    note('typed "n" → $location');

    // The item's context menu in the table.
    router.go(Routes.vault());
    await settle();
    await rightClick(listed(title));
    expect(find.text('Edit item…'), findsOneWidget);
    expect(find.text('Move to app…'), findsOneWidget);
    expect(find.text('Delete item…'), findsOneWidget);
    await shot('explorer-item-menu');
    await press(LogicalKeyboardKey.escape);
    if (find.text('Move to app…').evaluate().isNotEmpty) {
      note('Escape left the right-click menu open too');
      await tester.tapAt(
        tester.getCenter(find.byType(ShellStatusBar)),
        kind: PointerDeviceKind.mouse,
      );
      await settle();
    }
    expect(find.text('Move to app…'), findsNothing);
  }

  Future<void> _finalLock() async {
    await tap(
      find.descendant(
        of: find.byType(ShellToolbar),
        matching: find.bySemanticsLabel(RegExp('^Lock now')),
      ),
    );
    await until(() => session is Locked, what: 'the lock');
    await settle();
    expect(find.text('Unlock your vault'), findsOneWidget);
    expect(container.read(clipboardGuardProvider).isHoldingSecret, isFalse);
    await shot('locked-at-end');
  }
}

/// Reads the query back out of a vault location.
abstract final class VaultFilterQuery {
  static String? of(String location) =>
      Uri.parse(location).queryParameters['q'];
}
