import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Takes the keyboard into a menu while it's open and gives it back when
/// it closes, as each OS's menus do.
///
/// Opened from the keyboard, the menu's first command is highlighted.
/// Opened with the pointer, the menu holds the keyboard with nothing
/// highlighted until ↓ or ↑ picks its first or last command. ↑/↓ then move,
/// Return or Space runs the highlighted command, and Escape closes the menu
/// (the menu's own shortcuts); the keyboard goes back where it was.
class DesktopMenuFocus {
  DesktopMenuFocus(this._label) : _menu = FocusNode(debugLabel: '$_label menu');

  final String _label;
  final FocusNode _menu;
  final _items = <FocusNode>[];
  var _count = 0;

  /// Where the keyboard was when the menu opened.
  FocusNode? _returnTo;

  /// The focus node for command [i], to hand to the menu's item.
  FocusNode item(int i) {
    while (_items.length <= i) {
      _items.add(FocusNode(debugLabel: '$_label menu item ${_items.length}'));
    }
    return _items[i];
  }

  /// Holds the keyboard in a menu opened with the pointer. Wraps the menu,
  /// or, with no [child], sits in it as a zero-size first entry.
  Widget holder({Widget? child}) => Focus(
    focusNode: _menu,
    includeSemantics: false,
    onKeyEvent: _onKey,
    child: child ?? const SizedBox.shrink(),
  );

  /// Call as a menu of [count] commands opens.
  void opened({required int count, required bool fromKeyboard}) {
    _count = count;
    final now = FocusManager.instance.primaryFocus;
    // Opened again before it closed: keep where it first came from.
    if (!_inMenu(now)) _returnTo = now;
    // After the frame that builds the menu.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = fromKeyboard ? item(0) : _menu;
      if (target.context != null) target.requestFocus();
    });
  }

  /// Call as the menu closes: the keyboard goes back where it was, unless
  /// a command already took it somewhere else.
  void closed() {
    final back = _returnTo;
    _returnTo = null;
    final now = FocusManager.instance.primaryFocus;
    if (back != null && back.context != null && (now == null || _inMenu(now))) {
      back.requestFocus();
    }
  }

  bool _inMenu(FocusNode? node) => node == _menu || _items.contains(node);

  void dispose() {
    _menu.dispose();
    for (final node in _items) {
      node.dispose();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus || _count == 0) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      item(0).requestFocus();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      item(_count - 1).requestFocus();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }
}
