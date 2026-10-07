import '../../shared/ui.dart';

/// Settings pages on a phone (P3-07): narrower margins, room for the
/// floating bottom nav, and selects under their row text.
abstract final class SettingsLayout {
  static bool isNarrow(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600;

  static EdgeInsets padding(BuildContext context) => isNarrow(context)
      // 120: clear of the floating bottom nav, like the vault list.
      ? const EdgeInsets.fromLTRB(16, 16, 16, 120)
      : const EdgeInsets.fromLTRB(32, 24, 32, 32);
}
