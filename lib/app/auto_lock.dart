import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../data/vault_session.dart';
import '../shared/desktop/desktop_menu_bar.dart' show platformMenusActive;
import '../services/external_ui.dart';

/// Locks the vault on its own: after [autoLockProvider] of no input, when
/// the app comes back after the computer slept past that time, and on ⌘L
/// (Ctrl+L). On phones ([lockInBackgroundProvider]) also as soon as the app
/// goes to the background, unless DevVault itself opened the screen in
/// front ([ExternalUi]: a file picker, the share sheet). On quit it clears a
/// copied secret from the clipboard.
///
/// Idle time is measured on the wall clock ([clockProvider]) and checked
/// every [checkEvery], so a sleeping computer, whose timers stop, still
/// locks as soon as it wakes. Locking wipes the key, drops the decrypted
/// index and clears a copied secret ([VaultSessionNotifier.lock]).
class AutoLock extends ConsumerStatefulWidget {
  const AutoLock({super.key, required this.child});

  final Widget child;

  static const checkEvery = Duration(seconds: 5);

  @override
  ConsumerState<AutoLock> createState() => _AutoLockState();
}

class _AutoLockState extends ConsumerState<AutoLock> {
  late DateTime _lastInput = _now();
  Timer? _ticker;
  late final AppLifecycleListener _lifecycle;

  DateTime _now() => ref.read(clockProvider)();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _ticker = Timer.periodic(AutoLock.checkEvery, (_) => _check());
    _lifecycle = AppLifecycleListener(
      onResume: _check,
      // Hidden, not inactive: Face ID and the app switcher only make the
      // app inactive.
      onHide: _inBackground,
      // Quitting takes a copied secret off the clipboard too.
      onExitRequested: () async {
        await ref.read(clipboardGuardProvider).clearNow();
        return AppExitResponse.exit;
      },
    );
    ExternalUi.open.addListener(_externalUiChanged);
    // A fresh unlock starts a fresh idle period.
    ref.listenManual(vaultSessionProvider, (previous, next) {
      if (next is Unlocked && previous is! Unlocked) _touch();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _ticker?.cancel();
    _lifecycle.dispose();
    ExternalUi.open.removeListener(_externalUiChanged);
    super.dispose();
  }

  void _inBackground() {
    if (!ref.read(lockInBackgroundProvider) || ExternalUi.isOpen) return;
    _lock();
  }

  /// A picker or share sheet closed while DevVault stayed in the background.
  void _externalUiChanged() {
    if (ExternalUi.isOpen) return;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _inBackground();
    }
  }

  void _touch() => _lastInput = _now();

  void _check() {
    final after = ref.read(autoLockProvider);
    if (after == null) return;
    if (ref.read(vaultSessionProvider) is! Unlocked) return;
    if (_now().difference(_lastInput) >= after) _lock();
  }

  void _lock() => ref.read(vaultSessionProvider.notifier).lock();

  bool _onKey(KeyEvent event) {
    _touch();
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyL) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    if (!(keyboard.isMetaPressed || keyboard.isControlPressed) ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed ||
        ref.read(vaultSessionProvider) is! Unlocked ||
        // The macOS menu bar's Vault › Lock owns ⌘L there.
        platformMenusActive(context)) {
      return false;
    }
    _lock();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Translucent: watches every pointer without taking it from the app.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _touch(),
      onPointerMove: (_) => _touch(),
      onPointerHover: (_) => _touch(),
      onPointerSignal: (_) => _touch(),
      child: widget.child,
    );
  }
}
