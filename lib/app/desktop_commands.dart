import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// The commands the menu bar runs that only the open vault window can:
/// they need its search field, its current list or its navigator. The
/// window (DesktopShell) binds them while it is shown; while they're
/// unbound (lock screens) the menu shows them disabled.
class DesktopCommands extends ChangeNotifier {
  VoidCallback? _find;
  VoidCallback? _newItem;
  VoidCallback? _newSecureNote;
  VoidCallback? _importFile;
  VoidCallback? _quickOpen;

  VoidCallback? get find => _find;
  VoidCallback? get newItem => _newItem;
  VoidCallback? get newSecureNote => _newSecureNote;
  VoidCallback? get importFile => _importFile;
  VoidCallback? get quickOpen => _quickOpen;

  void bind({
    required VoidCallback find,
    required VoidCallback newItem,
    VoidCallback? newSecureNote,
    required VoidCallback importFile,
    required VoidCallback quickOpen,
  }) {
    _find = find;
    _newItem = newItem;
    _newSecureNote = newSecureNote;
    _importFile = importFile;
    _quickOpen = quickOpen;
    _changed();
  }

  void unbind() {
    _find = _newItem = _newSecureNote = _importFile = _quickOpen = null;
    _changed();
  }

  bool _disposed = false;

  /// The window binds while it builds, so the menu hears about it after
  /// the frame rather than mid-build.
  void _changed() {
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      notifyListeners();
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// The app's commands, or null outside the desktop layout.
  static DesktopCommands? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DesktopCommandsScope>()?.commands;
}

/// Makes [commands] reachable from the window below it.
class DesktopCommandsScope extends InheritedWidget {
  const DesktopCommandsScope({
    super.key,
    required this.commands,
    required super.child,
  });

  final DesktopCommands commands;

  @override
  bool updateShouldNotify(DesktopCommandsScope oldWidget) =>
      commands != oldWidget.commands;
}
