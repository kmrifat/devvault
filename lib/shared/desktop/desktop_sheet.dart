import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart' as mac;

import 'desktop_metrics.dart';
import 'desktop_theme.dart';

/// Opens [builder]'s [DesktopSheet] the way the OS shows a modal: on macOS
/// a sheet that slides down from under the toolbar, Fluent's dialog route on
/// Windows, Material's on Linux (Yaru-themed). Resolves with what the sheet
/// pops.
Future<T?> showDesktopSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return switch (context.desktopKit) {
    DesktopKit.macos => Navigator.of(context).push<T>(
      _MacosSheetRoute<T>(
        builder: builder,
        barrierLabel: MaterialLocalizations.of(context)
            .modalBarrierDismissLabel,
      ),
    ),
    DesktopKit.fluent => fl.showDialog<T>(context: context, builder: builder),
    DesktopKit.yaru => showDialog<T>(context: context, builder: builder),
  };
}

/// A sheet (design frames N03e, N04, N05, N08): a title, the content (a
/// [DesktopForm], usually), then the buttons at the bottom right, the
/// default action last. Escape closes it.
class DesktopSheet extends StatelessWidget {
  const DesktopSheet({
    super.key,
    required this.title,
    required this.child,
    required this.actions,
    this.width = 520,
    this.leadingAction,
    this.icon,
    this.message,
    this.subtitle,
  });

  final String title;

  /// A tile left of the title (the item's type, a conflict mark).
  final Widget? icon;

  /// A line or two of secondary text under the title: what the sheet is
  /// about, what happens next.
  final String? message;

  /// A richer line under the title than [message] (what the file was read
  /// as, with a check mark), in secondary text.
  final Widget? subtitle;

  final Widget child;

  /// Push buttons, Cancel first and the default action last.
  final List<Widget> actions;

  /// A button on the left of the bottom row (Delete, Keep Both).
  final Widget? leadingAction;

  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final header = _SheetHeader(
      title: title,
      icon: icon,
      message: message,
      subtitle: subtitle,
    );
    final buttons = Row(
      spacing: 8,
      children: [?leadingAction, const Spacer(), ...actions],
    );
    final body = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: FocusScope(
        autofocus: true,
        child: Material(
          type: MaterialType.transparency,
          child: DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: DesktopMetrics.bodySize,
              color: colors.text,
            ),
            // Sized to its content, and scrolls when that's taller than
            // the window allows.
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );
    return switch (context.desktopKit) {
      // Sheets hang from the toolbar, as in the frames.
      DesktopKit.macos => Align(
        alignment: Alignment.topCenter,
        child: Padding(
          // The route places it just under the toolbar.
          padding: const EdgeInsets.only(bottom: DesktopMetrics.toolbarHeight),
          child: SizedBox(
            width: width,
            child: mac.MacosSheet(
              insetPadding: EdgeInsets.zero,
              // The frames draw sheets a shade darker than the window, so the
              // white fields and tables inside stand out.
              backgroundColor: colors.groupBox,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [
                    header,
                    Flexible(child: body),
                    buttons,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      DesktopKit.fluent => fl.ContentDialog(
        constraints: BoxConstraints(maxWidth: width),
        title: header,
        content: body,
        actions: [buttons],
      ),
      DesktopKit.yaru => AlertDialog(
        title: header,
        content: SizedBox(width: width, child: body),
        actions: [buttons],
      ),
    };
  }
}

/// The sheet's title in bold, with its [icon] tile and [message] if any.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.title,
    this.icon,
    this.message,
    this.subtitle,
  });

  final String title;
  final Widget? icon;
  final String? message;
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final message = this.message;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 3,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: TextStyle(
              fontSize: DesktopMetrics.bodySize,
              fontWeight: FontWeight.w700,
              color: colors.text,
            ),
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
        if (subtitle case final subtitle?)
          DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: DesktopMetrics.secondarySize,
              color: colors.secondaryText,
            ),
            child: subtitle,
          ),
      ],
    );
    final icon = this.icon;
    if (icon == null) return text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        icon,
        Expanded(child: text),
      ],
    );
  }
}

/// A group box: a rounded, tinted panel that groups related rows (the
/// inspector's expiry, fields and file boxes; Settings sections).
/// [title] sits above it in secondary text.
class DesktopGroupBox extends StatelessWidget {
  const DesktopGroupBox({
    super.key,
    required this.child,
    this.title,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final String? title;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.groupBox,
        border: Border.all(color: colors.groupBoxStroke, width: 0.5),
        borderRadius: const BorderRadius.all(
          Radius.circular(DesktopMetrics.menuRadius + 2),
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
    final title = this.title;
    if (title == null) return box;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: DesktopMetrics.secondarySize,
            fontWeight: FontWeight.w600,
            color: colors.secondaryText,
          ),
        ),
        box,
      ],
    );
  }
}

/// A macOS sheet's route: the sheet slides down out of the toolbar's lower
/// edge (it is clipped there, as if it came from behind it) and back up
/// when it closes, over a light dimming of the window.
class _MacosSheetRoute<T> extends PopupRoute<T> {
  _MacosSheetRoute({required this.builder, required this.barrierLabel});

  final WidgetBuilder builder;

  @override
  final String barrierLabel;

  @override
  Color get barrierColor => const Color(0x26000000);

  @override
  bool get barrierDismissible => false;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 280);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final slide = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return Padding(
      padding: const EdgeInsets.only(top: DesktopMetrics.toolbarHeight),
      child: ClipRect(
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(slide),
          child: child,
        ),
      ),
    );
  }
}
