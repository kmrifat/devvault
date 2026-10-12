import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vault_core/vault_core.dart';

import '../../core/expiry.dart';
import '../../data/providers.dart';
import '../../data/vault_session.dart';
import '../../shared/ui.dart';

/// Sets, changes or removes the expiry date of [item] by hand (design
/// frame I9): a bc_ui calendar in a sheet, saved as "set by you". Only for
/// a date the file didn't give: a date read from the file is a fact and
/// isn't edited here.
Future<void> showExpiryDateSheet(BuildContext context, Item item) {
  assert(item.expiresSource != ExpirySource.file);
  return BCDialog.show<void>(
    context,
    builder: (_) => BCDialogContent(child: ExpiryDateSheet(item: item)),
  );
}

class ExpiryDateSheet extends ConsumerStatefulWidget {
  const ExpiryDateSheet({super.key, required this.item});

  final Item item;

  @override
  ConsumerState<ExpiryDateSheet> createState() => _ExpiryDateSheetState();
}

class _ExpiryDateSheetState extends ConsumerState<ExpiryDateSheet> {
  /// The picked day, as the calendar shows it (local).
  late DateTime? _picked = widget.item.expiresAt?.toLocal();
  bool _saving = false;

  Future<void> _save({bool remove = false}) async {
    final picked = _picked;
    if (!remove && picked == null) return;
    setState(() => _saving = true);
    final item = widget.item;
    // A day, like the editor stores it: midnight UTC of the picked date.
    final updated = remove
        ? item.copyWith(clearExpiry: true)
        : item.copyWith(
            expiresAt: DateTime.utc(picked!.year, picked.month, picked.day),
            expiresSource: ExpirySource.user,
          );
    await ref.read(vaultSessionProvider.notifier).saveItem(updated);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final now = ref.watch(clockProvider)();
    final picked = _picked;
    final hadDate = item.expiresAt != null;
    final changed =
        picked != null &&
        (item.expiresAt == null ||
            !DateUtils.isSameDay(picked, item.expiresAt!.toLocal()));
    final pickedUtc = picked == null
        ? null
        : DateTime.utc(picked.year, picked.month, picked.day);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: BCSpacing.md,
      children: [
        Row(
          spacing: BCSpacing.sm,
          children: [
            BCCloseButton(onPressed: () => Navigator.of(context).pop()),
            Expanded(
              child: Column(
                spacing: 2,
                children: [
                  const BCText('Expiry date', weight: BCTextWeight.semibold),
                  BCText(
                    item.title,
                    type: BCTextType.bodyXs,
                    color: BCTextColor.muted,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            BCButton(
              size: BCButtonSize.sm,
              isIconOnly: true,
              isDisabled: !changed || _saving,
              onPressed: _save,
              child: const Icon(
                LucideIcons.check,
                size: 18,
                semanticLabel: 'Save',
              ),
            ),
          ],
        ),
        BCCard(
          variant: BCCardVariant.secondary,
          padding: const EdgeInsets.all(BCSpacing.md - 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              Icon(LucideIcons.info, size: 18, color: context.bcTheme.muted),
              Expanded(
                child: BCText(
                  hadDate
                      ? 'You set this date; the file doesn’t state one. '
                            'Change it or remove it.'
                      : 'The file doesn’t state an expiry date. Set one only '
                            'if you know it; it’s saved as “set by you”.',
                  type: BCTextType.bodySm,
                  color: BCTextColor.muted,
                ),
              ),
            ],
          ),
        ),
        BCCalendar(
          initialDate: picked ?? now,
          selectedDate: picked,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100, 12, 31),
          onDateSelected: (day) => setState(() => _picked = day),
        ),
        if (pickedUtc != null)
          BCListGroup(
            children: [
              BCListGroupItem(
                content: Row(
                  spacing: BCSpacing.sm,
                  children: [
                    const BCText('Expires', color: BCTextColor.muted),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        spacing: 2,
                        children: [
                          BCText(
                            DateFormat.yMMMEd().format(picked!),
                            weight: BCTextWeight.semibold,
                            align: TextAlign.end,
                          ),
                          BCText(
                            pickedUtc.isAfter(now)
                                ? 'in ${timeLeft(pickedUtc, now)}'
                                : timeAgo(pickedUtc, now),
                            type: BCTextType.bodyXs,
                            color: BCTextColor.muted,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        if (hadDate)
          BCButton(
            variant: BCButtonVariant.dangerSoft,
            fullWidth: true,
            isDisabled: _saving,
            onPressed: () => _save(remove: true),
            startContent: const Icon(LucideIcons.calendarX2, size: 16),
            child: const Text('Remove date'),
          ),
      ],
    );
  }
}
