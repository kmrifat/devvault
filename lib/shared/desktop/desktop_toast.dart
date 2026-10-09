import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';

import 'desktop_button.dart';
import 'desktop_icon_button.dart';
import 'desktop_metrics.dart';
import 'desktop_symbols.dart';
import 'desktop_theme.dart';

/// What a [showDesktopToast] reports.
enum DesktopToastKind { info, success, danger }

/// Shows a short, passing message ("“Upload keystore” moved to Kitchenly")
/// the way the OS does, with an optional [actionLabel] such as Undo:
///
/// - macOS: a banner like Notification Center's, at the top right of the
///   window under the toolbar. It closes after [duration] (zero keeps it),
///   or with its ×, which shows on hover; hovering keeps it open.
/// - Windows: Fluent's `InfoBar`, at the bottom of the window.
/// - Linux: a Yaru snackbar, at the bottom of the window.
///
/// One shows at a time: a new message replaces the one showing (the
/// `InfoBar`s on Windows stack, as Fluent's do). Never pass a secret: the
/// title and message are plain text on screen.
void showDesktopToast(
  BuildContext context, {
  required String title,
  String? message,
  DesktopToastKind kind = DesktopToastKind.info,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
}) {
  final kit = context.desktopKit;
  if (kit == DesktopKit.fluent) {
    fl.displayInfoBar(
      context,
      duration: duration,
      builder: (context, close) => fl.InfoBar(
        title: Text(title),
        content: message == null ? null : Text(message),
        severity: switch (kind) {
          DesktopToastKind.info => fl.InfoBarSeverity.info,
          DesktopToastKind.success => fl.InfoBarSeverity.success,
          DesktopToastKind.danger => fl.InfoBarSeverity.error,
        },
        action: actionLabel == null
            ? null
            : fl.Button(
                onPressed: () {
                  close();
                  onAction?.call();
                },
                child: Text(actionLabel),
              ),
        onClose: close,
      ),
    );
    return;
  }
  final current = _current;
  if (current != null && current.mounted) current.remove();
  late final OverlayEntry entry;
  // The root overlay is under the app's DesktopTheme, so the toast gets
  // the kit and colours from there.
  entry = OverlayEntry(
    builder: (_) => _Toast(
      kit: kit,
      title: title,
      message: message,
      kind: kind,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
      onClosed: () {
        if (entry.mounted) entry.remove();
        if (_current == entry) _current = null;
      },
    ),
  );
  _current = entry;
  Overlay.of(context, rootOverlay: true).insert(entry);
}

/// The macOS or Yaru toast on screen, if any.
OverlayEntry? _current;

class _Toast extends StatefulWidget {
  const _Toast({
    required this.kit,
    required this.title,
    required this.message,
    required this.kind,
    required this.actionLabel,
    required this.onAction,
    required this.duration,
    required this.onClosed,
  });

  final DesktopKit kit;
  final String title;
  final String? message;
  final DesktopToastKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  final VoidCallback onClosed;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final _show = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..forward();
  Timer? _timer;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _wait();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _show.dispose();
    super.dispose();
  }

  /// Closes after [_Toast.duration]; zero keeps it until closed.
  void _wait() {
    _timer?.cancel();
    if (widget.duration == Duration.zero) return;
    _timer = Timer(widget.duration, _close);
  }

  Future<void> _close() async {
    _timer?.cancel();
    if (!mounted) return;
    await _show.reverse();
    widget.onClosed();
  }

  void _hover(bool on) {
    setState(() => _hovered = on);
    if (on) {
      _timer?.cancel();
    } else {
      _wait();
    }
  }

  @override
  Widget build(BuildContext context) {
    final macos = widget.kit == DesktopKit.macos;
    final curve = CurvedAnimation(parent: _show, curve: Curves.easeOut);
    final card = MouseRegion(
      onEnter: (_) => _hover(true),
      onExit: (_) => _hover(false),
      child: Semantics(
        liveRegion: true,
        container: true,
        child: macos ? _banner(context) : _snackbar(context),
      ),
    );
    return Positioned(
      top: macos ? DesktopMetrics.toolbarHeight + 8 : null,
      right: macos ? 12 : null,
      bottom: macos ? null : 24,
      left: macos ? null : 0,
      width: macos ? null : MediaQuery.sizeOf(context).width,
      child: FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween(
            begin: macos ? const Offset(0.15, 0) : const Offset(0, 0.3),
            end: Offset.zero,
          ).animate(curve),
          child: macos ? card : Center(child: card),
        ),
      ),
    );
  }

  void _act() {
    _close();
    widget.onAction?.call();
  }

  /// macOS: a Notification Center–style banner.
  Widget _banner(BuildContext context) {
    final colors = context.desktopColors;
    final actionLabel = widget.actionLabel;
    final message = widget.message;
    final (symbol, tint) = switch (widget.kind) {
      DesktopToastKind.info => (DesktopSymbol.info, colors.accentIcon),
      DesktopToastKind.success => (DesktopSymbol.success, colors.success),
      DesktopToastKind.danger => (DesktopSymbol.error, colors.danger),
    };
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: DesktopMetrics.toastWidth,
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: colors.menu,
          border: Border.all(color: colors.groupBoxStroke, width: 0.5),
          borderRadius: const BorderRadius.all(
            Radius.circular(DesktopMetrics.panelRadius),
          ),
          boxShadow: [
            BoxShadow(
              color: colors.shadow,
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: 10,
          children: [
            DesktopIcon(symbol, size: 18, color: tint),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: 2,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: DesktopMetrics.bodySize,
                      fontWeight: FontWeight.w600,
                      color: colors.text,
                    ),
                  ),
                  if (message != null)
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: DesktopMetrics.secondarySize,
                        color: colors.secondaryText,
                      ),
                    ),
                ],
              ),
            ),
            if (actionLabel != null)
              DesktopButton(label: actionLabel, onPressed: _act),
            SizedBox.square(
              dimension: 20,
              child: _hovered
                  ? DesktopIconButton(
                      symbol: DesktopSymbol.remove,
                      tooltip: 'Close',
                      size: 10,
                      onPressed: _close,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  /// Linux: a floating snackbar, drawn from the Yaru theme's snackbar
  /// style.
  Widget _snackbar(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.snackBarTheme;
    final scheme = theme.colorScheme;
    final text = style.contentTextStyle?.color ?? scheme.onInverseSurface;
    final actionLabel = widget.actionLabel;
    final message = widget.message;
    return Material(
      color: style.backgroundColor ?? scheme.inverseSurface,
      elevation: style.elevation ?? 6,
      shape:
          style.shape ??
          const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(DesktopMetrics.menuRadius),
            ),
          ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: DesktopMetrics.toastMinWidth,
          maxWidth: DesktopMetrics.toastMaxWidth,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      style: (style.contentTextStyle ?? const TextStyle())
                          .copyWith(color: text),
                    ),
                    if (message != null)
                      Text(
                        message,
                        style: TextStyle(
                          color: text.withValues(alpha: 0.8),
                          fontSize: DesktopMetrics.secondarySize,
                        ),
                      ),
                  ],
                ),
              ),
              if (actionLabel != null)
                TextButton(
                  onPressed: _act,
                  style: TextButton.styleFrom(
                    foregroundColor:
                        style.actionTextColor ?? scheme.inversePrimary,
                  ),
                  child: Text(actionLabel),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
