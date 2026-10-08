import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart' as mac;

import 'desktop_metrics.dart';
import 'desktop_theme.dart';

/// Opens [builder]'s [DesktopSheet] the way the OS shows a modal: a
/// `MacosSheet` on macOS, Fluent's dialog route on Windows, Material's on
/// Linux (Yaru-themed). Resolves with what the sheet pops.
Future<T?> showDesktopSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return switch (context.desktopKit) {
    DesktopKit.macos => mac.showMacosSheet<T>(
      context: context,
      builder: builder,
    ),
    DesktopKit.fluent => fl.showDialog<T>(context: context, builder: builder),
    DesktopKit.yaru => showDialog<T>(context: context, builder: builder),
  };
}

/// A sheet (design frames N03e, N04, N05, N08): a title, the content (a
/// [DesktopForm], usually), then the buttons at the bottom right, the
/// default action last. Escape closes it.
///
/// On macOS it hangs from the top of the window, under the toolbar, as a
/// sheet does; Windows and Linux centre their dialogs.
class DesktopSheet extends StatelessWidget {
  const DesktopSheet({
    super.key,
    required this.title,
    required this.child,
    required this.actions,
    this.width = 520,
    this.leadingAction,
    this.leading,
    this.subtitle,
  });

  final String title;
  final Widget child;

  /// A tile beside the title (the item type's icon).
  final Widget? leading;

  /// A line under the title (what the file was read as).
  final Widget? subtitle;

  /// Push buttons, Cancel first and the default action last.
  final List<Widget> actions;

  /// A button on the left of the bottom row (Delete, Keep Both).
  final Widget? leadingAction;

  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final heading = Text(
      title,
      style: TextStyle(
        fontSize: DesktopMetrics.bodySize + 2,
        fontWeight: FontWeight.w600,
        color: colors.text,
      ),
    );
    final leading = this.leading;
    final subtitle = this.subtitle;
    final header = leading == null && subtitle == null
        ? heading
        : Row(
            spacing: 10,
            children: [
              ?leading,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    heading,
                    if (subtitle != null)
                      DefaultTextStyle.merge(
                        style: TextStyle(
                          fontSize: DesktopMetrics.secondarySize,
                          color: colors.secondaryText,
                        ),
                        child: subtitle,
                      ),
                  ],
                ),
              ),
            ],
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
            child: child,
          ),
        ),
      ),
    );
    return switch (context.desktopKit) {
      DesktopKit.macos => Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(
            top: DesktopMetrics.toolbarHeight + 2,
            bottom: DesktopMetrics.toolbarHeight,
          ),
          child: SizedBox(
            width: width,
            child: mac.MacosSheet(
              insetPadding: EdgeInsets.zero,
              backgroundColor: colors.groupBox,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
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
