import '../../shared/desktop_ui.dart'
    show DesktopIcon, DesktopMetrics, DesktopSymbol, DesktopThemeContext;
import '../../shared/ui.dart';

/// Shared by the import sheets: the phone breakpoint, field labels and the
/// app / platform / environment pickers.

/// A phone (B4, B4b) rather than a wide screen (D04).
bool isNarrowSheet(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 600;

/// A label above a control that has none of its own, lined up with bc_ui's
/// field labels.
class SheetLabel extends StatelessWidget {
  const SheetLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Lines up with bc_ui's own field labels.
      padding: const EdgeInsets.only(left: 6, bottom: BCSpacing.xs),
      child: BCText(text, type: BCTextType.bodySm, weight: BCTextWeight.medium),
    );
  }
}

/// A select over [options] (value → label) with a "none" choice first.
/// Phones pick from a sheet (B4), wider screens from a popover.
class PlaceChoice extends StatelessWidget {
  const PlaceChoice({
    super.key,
    required this.label,
    required this.none,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String none;
  final String? value;
  final Map<String, String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetLabel(label),
        BCSelect<String>(
          listLabel: label,
          presentation: isNarrowSheet(context)
              ? BCSelectPresentation.bottomSheet
              : BCSelectPresentation.popover,
          value: value ?? '',
          items: [
            BCSelectItem(value: '', label: none),
            for (final MapEntry(:key, value: text) in options.entries)
              BCSelectItem(value: key, label: text),
          ],
          onValueChange: (v) => onChanged(v.isEmpty ? null : v),
        ),
      ],
    );
  }
}

/// App, platform and environment: one row on a wide screen; on a phone the
/// app gets its own row, as in B4, so no select is too narrow to read.
class PlaceFields extends StatelessWidget {
  const PlaceFields({
    super.key,
    required this.app,
    required this.platform,
    required this.environment,
  });

  final Widget app;
  final Widget platform;
  final Widget environment;

  @override
  Widget build(BuildContext context) {
    final narrow = isNarrowSheet(context);
    final pair = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: BCSpacing.sm,
      children: [
        if (!narrow) Expanded(child: app),
        Expanded(child: platform),
        Expanded(child: environment),
      ],
    );
    if (!narrow) return pair;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: BCSpacing.md,
      children: [app, pair],
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop sheets (N04 import, N03e item editor): pieces both forms share.
// ---------------------------------------------------------------------------

/// What a platform or environment combo box suggests: SPEC §6.1's values
/// ([spec]), then any other value the vault already [used], A–Z. They are
/// only suggestions; the user may type anything.
List<String> placeSuggestions(List<String> spec, Iterable<String?> used) => [
  ...spec,
  ...({
    for (final value in used)
      if (value != null && value.trim().isNotEmpty && !spec.contains(value))
        value,
  }.toList()..sort()),
];

/// A platform or environment as the user typed it, without the spaces
/// around it; null when they left it empty. Never a default.
String? typedPlace(String text) {
  final value = text.trim();
  return value.isEmpty ? null : value;
}

/// How a [SheetNote]'s note reads: a plain hint, something still needed,
/// or a problem.
enum NoteTone { hint, needed, problem }

/// A desktop form control with a short note: beside it when the control
/// has a [width] (as in N04: "From the file name", "Required · not in the
/// file"), else under it.
class SheetNote extends StatelessWidget {
  const SheetNote({
    super.key,
    required this.control,
    this.note,
    this.tone = NoteTone.hint,
    this.width,
  });

  final Widget control;
  final String? note;
  final NoteTone tone;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    final width = this.width;
    final sized = width == null
        ? control
        : SizedBox(width: width, child: control);
    if (note == null) {
      return width == null
          ? control
          : Align(alignment: AlignmentDirectional.centerStart, child: sized);
    }
    final colors = context.desktopColors;
    final text = Text(
      note,
      style: TextStyle(
        fontSize: DesktopMetrics.secondarySize,
        color: switch (tone) {
          NoteTone.hint => colors.secondaryText,
          NoteTone.needed => colors.onWarningBadge,
          NoteTone.problem => colors.danger,
        },
      ),
    );
    if (width == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 3,
        children: [control, text],
      );
    }
    return Row(
      spacing: DesktopMetrics.formLabelGap,
      children: [
        sized,
        Flexible(child: text),
      ],
    );
  }
}

/// Where a value came from, as a small outlined tag ("From the file").
class SourceTag extends StatelessWidget {
  const SourceTag(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.groupBoxInner,
        border: Border.all(color: colors.groupBoxStroke),
        borderRadius: const BorderRadius.all(
          Radius.circular(DesktopMetrics.tokenRadius),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            DesktopIcon(DesktopSymbol.document, size: 11),
            Text(
              text,
              style: TextStyle(
                fontSize: DesktopMetrics.secondarySize,
                color: colors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A one-line box in a sheet: an icon and a sentence (the expiry, a
/// duplicate, a warning from the parser). [problem] draws it in red.
class SheetNotice extends StatelessWidget {
  const SheetNotice({
    super.key,
    required this.symbol,
    required this.child,
    this.problem = false,
  });

  final DesktopSymbol symbol;
  final Widget child;
  final bool problem;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.groupBoxInner,
        border: Border.all(color: colors.groupBoxStroke, width: 0.5),
        borderRadius: const BorderRadius.all(
          Radius.circular(DesktopMetrics.menuRadius + 2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          spacing: 8,
          children: [
            DesktopIcon(
              symbol,
              size: 14,
              color: problem ? colors.danger : colors.secondaryText,
            ),
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: DesktopMetrics.bodySize - 1,
                  color: problem ? colors.danger : colors.text,
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
