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
