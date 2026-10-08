import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'desktop_metrics.dart';
import 'desktop_theme.dart';

/// The tile at the top of a lock screen.
enum DesktopLockMark {
  /// The app's own mark: the vault glyph in white on the accent, as on the
  /// app icon (unlock, create, join).
  app,

  /// A life buoy on the warning tint (recovery kit, recovery key).
  recoveryKey,
}

/// A lock screen (design frames N00–N02): unlock, create a vault, the
/// recovery kit, recover and join. They show no vault window around them:
/// a compact column [DesktopMetrics.lockWidth] wide, centred in the window
/// on the lock-window colour, with the mark, a title and a message, then
/// [children].
///
/// [centred] centres everything (unlock); otherwise the column reads from
/// the left like a setup assistant, with [step] ("Step 1 of 3") top right.
/// [footer] is the bottom row under a separator: a link on the left, the
/// default button on the right. [footnote] is a last line of small print.
///
/// The same layout serves every kit; the controls inside draw themselves.
class DesktopLockWindow extends StatelessWidget {
  const DesktopLockWindow({
    super.key,
    required this.title,
    required this.children,
    this.message,
    this.mark = DesktopLockMark.app,
    this.step,
    this.centred = false,
    this.footer,
    this.footnote,
  });

  final String title;
  final String? message;
  final List<Widget> children;
  final DesktopLockMark mark;
  final String? step;
  final bool centred;
  final Widget? footer;
  final Widget? footnote;

  /// Space between the column's edges and its content.
  static const double _inset = 44;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final message = this.message;
    final step = this.step;
    final footer = this.footer;
    final footnote = this.footnote;
    final markTile = _MarkTile(mark: mark, large: centred);
    final align = centred ? TextAlign.center : TextAlign.start;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: _inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: centred
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.stretch,
        children: [
          if (step == null)
            Align(
              alignment: centred ? Alignment.center : Alignment.centerLeft,
              child: markTile,
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                markTile,
                const Spacer(),
                Text(
                  step,
                  style: TextStyle(
                    fontSize: DesktopMetrics.secondarySize,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
          SizedBox(height: centred ? 16 : 14),
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: align,
              style: TextStyle(
                fontSize: centred ? 17 : 20,
                fontWeight: centred ? FontWeight.w600 : FontWeight.w700,
                color: colors.text,
              ),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: align,
              style: TextStyle(
                fontSize: DesktopMetrics.bodySize,
                height: 1.4,
                color: colors.secondaryText,
              ),
            ),
          ],
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );

    final column = SizedBox(
      width: DesktopMetrics.lockWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          content,
          if (footer != null) ...[
            const SizedBox(height: 32),
            SizedBox(
              height: 1,
              child: ColoredBox(color: colors.innerSeparator),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: footer,
            ),
          ],
          if (footnote != null) ...[
            const SizedBox(height: 48),
            Center(child: footnote),
          ],
        ],
      ),
    );

    return Scaffold(
      backgroundColor: colors.lockWindow,
      body: DefaultTextStyle.merge(
        style: TextStyle(fontSize: DesktopMetrics.bodySize, color: colors.text),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 80).clamp(
                  0,
                  double.infinity,
                ),
              ),
              child: Center(child: column),
            ),
          ),
        ),
      ),
    );
  }
}

class _MarkTile extends StatelessWidget {
  const _MarkTile({required this.mark, required this.large});

  final DesktopLockMark mark;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final size = large ? 64.0 : 48.0;
    final (fill, glyph, icon) = switch (mark) {
      DesktopLockMark.app => (
        colors.accent,
        colors.onAccent,
        LucideIcons.vault,
      ),
      DesktopLockMark.recoveryKey => (
        colors.warningBadge,
        colors.onWarningBadge,
        LucideIcons.lifeBuoy,
      ),
    };
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: fill,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.all(Radius.circular(size * 0.225)),
          ),
        ),
        child: SizedBox.square(
          dimension: size,
          child: Icon(icon, size: size * 0.5, color: glyph),
        ),
      ),
    );
  }
}

/// A problem with the control above it ("Use at least 12 characters"), in
/// the danger colour, lined up with the controls of a form whose label
/// column is [indent] wide. Screen readers announce it when it appears.
class DesktopFieldMessage extends StatelessWidget {
  const DesktopFieldMessage(this.message, {super.key, this.indent});

  final String message;

  /// The form's label column; null lines it up with the left edge.
  final double? indent;

  @override
  Widget build(BuildContext context) {
    final indent = this.indent;
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: indent == null ? 0 : indent + DesktopMetrics.formLabelGap,
        top: 2,
      ),
      child: Semantics(
        liveRegion: true,
        child: Text(
          message,
          style: TextStyle(
            fontSize: DesktopMetrics.secondarySize,
            color: context.desktopColors.danger,
          ),
        ),
      ),
    );
  }
}

/// A white box with a hairline border on the lock window: the Argon2 note,
/// the recovery key.
class DesktopLockBox extends StatelessWidget {
  const DesktopLockBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(10),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.groupBoxInner,
        border: Border.all(color: colors.groupBoxStroke),
        borderRadius: const BorderRadius.all(
          Radius.circular(DesktopMetrics.menuRadius + 2),
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
