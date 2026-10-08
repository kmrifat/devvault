import 'package:intl/intl.dart';
import 'package:vault_core/vault_core.dart';

import '../../core/expiry.dart';
import '../../shared/ui.dart';

/// One item in the phone list (design frame B2): type tile, title, file
/// name or type, and a conflict or expiry chip. The desktop shows items in
/// the vault table (`vault_list_pane.dart`).
class VaultItemRow extends StatefulWidget {
  const VaultItemRow({
    super.key,
    required this.item,
    required this.selected,
    required this.now,
    required this.onTap,
  });

  final Item item;
  final bool selected;
  final DateTime now;
  final VoidCallback onTap;

  @override
  State<VaultItemRow> createState() => _VaultItemRowState();
}

class _VaultItemRowState extends State<VaultItemRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final item = widget.item;
    final file = item.attachments.firstOrNull?.filename;
    final typeLabel = item.type?.label ?? item.typeName;

    return Semantics(
      button: true,
      selected: widget.selected,
      label: '${item.title}, $typeLabel',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: ColoredBox(
            color: widget.selected
                ? bc.accentSoft
                : _hovered
                ? bc.surfaceHover
                : bc.surface.withValues(alpha: 0),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                spacing: 12,
                children: [
                  TypeIconTile(type: item.type ?? ItemType.genericFile),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 3,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.2,
                            fontWeight: BCTypography.semiBold,
                            color: bc.foreground,
                          ),
                        ),
                        if (file != null)
                          MonoText(
                            file,
                            middleEllipsis: true,
                            style: TextStyle(
                              fontSize: BCTypography.sizeXs,
                              color: bc.muted,
                            ),
                          )
                        else
                          BCText(
                            typeLabel,
                            type: BCTextType.bodyXs,
                            color: BCTextColor.muted,
                            maxLines: 1,
                          ),
                      ],
                    ),
                  ),
                  ?_trailing(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A conflict first, then the expiry: a chip when it needs attention,
  /// the month otherwise.
  Widget? _trailing(BuildContext context) {
    final item = widget.item;
    if (item.conflict != null) {
      return const BCChip(
        size: BCChipSize.sm,
        variant: BCChipVariant.secondary,
        color: BCChipColor.defaultColor,
        startContent: Icon(LucideIcons.gitMerge, size: 12),
        child: Text('Conflict'),
      );
    }
    final expiresAt = item.expiresAt;
    return switch (ExpiryState.of(item, widget.now)) {
      ExpiryState.none => null,
      ExpiryState.expired => const BCChip(
        size: BCChipSize.sm,
        variant: BCChipVariant.soft,
        color: BCChipColor.danger,
        child: Text('Expired'),
      ),
      ExpiryState.soon => BCChip(
        size: BCChipSize.sm,
        variant: BCChipVariant.soft,
        color: BCChipColor.warning,
        child: Text(daysLeft(expiresAt!, widget.now)),
      ),
      ExpiryState.valid => BCText(
        DateFormat.yMMM().format(expiresAt!.toLocal()),
        type: BCTextType.bodyXs,
        color: BCTextColor.muted,
      ),
    };
  }
}
