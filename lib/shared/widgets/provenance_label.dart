import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:vault_core/vault_core.dart';

/// Says where an expiry date came from: the file, the user, or nowhere.
///
/// Every expiry the app shows carries one of these, because the app only
/// shows facts it can trace.
class ProvenanceLabel extends StatelessWidget {
  const ProvenanceLabel({super.key, required this.source, this.fileKind});

  /// `null` when the item has no known expiry.
  final ExpirySource? source;

  /// What the date was read from, e.g. `certificate` or `profile`. Only
  /// used when [source] is [ExpirySource.file].
  final String? fileKind;

  /// The label text for [source], also used by screen readers.
  static String textFor(ExpirySource? source, {String? fileKind}) =>
      switch (source) {
        ExpirySource.file => 'From ${fileKind ?? 'file'}',
        ExpirySource.user => 'Set by you',
        null => 'Expiry unknown',
      };

  @override
  Widget build(BuildContext context) {
    final icon = switch (source) {
      ExpirySource.file => LucideIcons.fileBadge,
      ExpirySource.user => LucideIcons.userPen,
      null => LucideIcons.circleHelp,
    };
    return BCChip(
      size: BCChipSize.sm,
      variant: BCChipVariant.soft,
      color: BCChipColor.defaultColor,
      startContent: Icon(icon, size: 14),
      child: Text(textFor(source, fileKind: fileKind)),
    );
  }
}
