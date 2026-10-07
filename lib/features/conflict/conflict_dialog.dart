import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vault_core/vault_core.dart';

import '../../data/vault_session.dart';
import '../../shared/ui.dart';
import 'conflict_resolution.dart';

/// Design frame D05: resolves an item changed on two devices at once, one
/// kept version at a time. Every difference needs an explicit choice;
/// "Keep both" turns the other version into an item of its own.
Future<void> showConflictDialog(BuildContext context, Item item) =>
    BCDialog.show<void>(
      context,
      builder: (_) => BCDialogContent(
        width: 760,
        showCloseButton: true,
        child: ConflictDialog(itemId: item.id),
      ),
    );

class ConflictDialog extends ConsumerStatefulWidget {
  const ConflictDialog({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<ConflictDialog> createState() => _ConflictDialogState();
}

class _ConflictDialogState extends ConsumerState<ConflictDialog> {
  final _choices = <String, ConflictSide>{};
  bool _reveal = false;
  bool _busy = false;

  Future<void> _save(List<Item> items) async {
    setState(() => _busy = true);
    try {
      final session = ref.read(vaultSessionProvider.notifier);
      for (final item in items) {
        await session.saveItem(item);
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _keepBoth(Item mine, Item theirs) async {
    final session = ref.read(vaultSessionProvider.notifier);
    final copy = session
        .newItem(
          theirs.type ?? ItemType.genericFile,
          '${theirs.title} (other device)',
        )
        .copyWith(
          appId: theirs.appId,
          platform: theirs.platform,
          environment: theirs.environment,
          tags: theirs.tags,
          fields: theirs.fields,
          attachments: theirs.attachments,
          expiresAt: theirs.expiresAt,
          expiresSource: theirs.expiresSource,
          notes: theirs.notes,
        );
    await _save([copy, dropVersion(mine, theirs)]);
  }

  Future<void> _deleteAnyway(Item mine) async {
    setState(() => _busy = true);
    try {
      await ref.read(vaultSessionProvider.notifier).deleteItem(mine.id);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(vaultSessionProvider);
    if (session is! Unlocked) return const SizedBox.shrink();
    final mine = session.index.items[widget.itemId];
    if (mine == null) return const SizedBox.shrink();
    final conflict = Conflict.of(mine);

    if (conflict.versions.isEmpty) {
      return _Deletion(
        item: mine,
        deletion: conflict.deletions.firstOrNull,
        busy: _busy,
        onKeep: () => _save([keepDespiteDeletion(mine)]),
        onDelete: () => _deleteAnyway(mine),
      );
    }

    final theirs = conflict.versions.first;
    final rows = conflictRows(mine, theirs, session.index.apps);
    final complete = rows.every((r) => _choices.containsKey(r.key));
    final date = DateFormat.yMMMd();
    final mineNewer = mine.rev > theirs.rev;
    void chooseAll(ConflictSide side) => setState(() {
      for (final r in rows) {
        _choices[r.key] = side;
      }
    });

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BCDialogTitle('Resolve conflict'),
        const SizedBox(height: BCSpacing.xs),
        BCDialogDescription(
          '“${mine.title}” was changed on this device and another at the same '
          'time. Pick the value to keep for each difference; nothing changes '
          'until you do.',
        ),
        if (conflict.versions.length > 1) ...[
          const SizedBox(height: BCSpacing.sm),
          BCText(
            '${conflict.versions.length} versions to go through · this is '
            'the first',
            type: BCTextType.bodySm,
            color: BCTextColor.muted,
          ),
        ],
        const SizedBox(height: BCSpacing.md),
        Row(
          children: [
            BCLinkButton(
              onPressed: () => chooseAll(ConflictSide.mine),
              child: const Text('Keep all from this device'),
            ),
            const SizedBox(width: BCSpacing.md),
            BCLinkButton(
              onPressed: () => chooseAll(ConflictSide.theirs),
              child: const Text('Keep all from the other device'),
            ),
            const Spacer(),
            if (rows.any((r) => r.secret))
              BCButton(
                size: BCButtonSize.sm,
                variant: BCButtonVariant.ghost,
                onPressed: () => setState(() => _reveal = !_reveal),
                startContent: Icon(
                  _reveal ? LucideIcons.eyeOff : LucideIcons.eye,
                  size: 15,
                ),
                child: Text(_reveal ? 'Hide secrets' : 'Show secrets'),
              ),
          ],
        ),
        const SizedBox(height: BCSpacing.sm),
        Row(
          spacing: BCSpacing.sm,
          children: [
            const SizedBox(width: 140),
            Expanded(
              child: BCText(
                'This device · ${date.format(mine.updatedAt.toLocal())}'
                '${mineNewer ? ' · newer' : ''}',
                type: BCTextType.bodyXs,
                color: BCTextColor.muted,
              ),
            ),
            Expanded(
              child: BCText(
                'Other device · ${date.format(theirs.updatedAt.toLocal())}'
                '${mineNewer ? '' : ' · newer'}',
                type: BCTextType.bodyXs,
                color: BCTextColor.muted,
              ),
            ),
          ],
        ),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(top: BCSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: BCSpacing.sm,
              children: [
                SizedBox(
                  width: 140,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: BCText(
                      row.label,
                      type: BCTextType.bodySm,
                      color: BCTextColor.muted,
                    ),
                  ),
                ),
                for (final side in ConflictSide.values)
                  Expanded(
                    child: _Choice(
                      label:
                          '${row.label} from '
                          '${side == ConflictSide.mine ? 'this device' : 'the other device'}',
                      value: side == ConflictSide.mine ? row.mine : row.theirs,
                      masked: row.secret && !_reveal,
                      selected: _choices[row.key] == side,
                      onTap: () => setState(() => _choices[row.key] = side),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: BCSpacing.lg),
        Row(
          spacing: BCSpacing.sm,
          children: [
            BCButton(
              variant: BCButtonVariant.secondary,
              isDisabled: _busy,
              onPressed: () => _keepBoth(mine, theirs),
              startContent: const Icon(LucideIcons.copy, size: 15),
              child: const Text('Keep both'),
            ),
            const Spacer(),
            BCButton(
              variant: BCButtonVariant.secondary,
              isDisabled: _busy,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            BCButton(
              isDisabled: _busy || !complete,
              onPressed: () => _save([
                resolveConflict(mine: mine, theirs: theirs, choices: _choices),
              ]),
              child: const Text('Resolve'),
            ),
          ],
        ),
      ],
    );
  }
}

/// One side of one difference: tap to keep it.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.masked,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? value;
  final bool masked;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final shape = BCShapes.continuous(
      BCRadius.xxl,
      side: BorderSide(
        color: selected ? bc.accent : bc.border,
        width: selected ? 2 : 1,
      ),
    );
    final value = this.value;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: shape,
              color: selected ? bc.accentSoft : bc.surface,
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: BCSpacing.sm,
                children: [
                  Icon(
                    selected ? LucideIcons.circleDot : LucideIcons.circle,
                    size: 16,
                    color: selected ? bc.accent : bc.muted,
                  ),
                  Expanded(
                    child: value == null
                        ? const BCText(
                            'Not set',
                            type: BCTextType.bodySm,
                            color: BCTextColor.muted,
                          )
                        : masked
                        ? Text(
                            SecretRow.mask,
                            style: TextStyle(
                              color: bc.foreground,
                              letterSpacing: 2,
                            ),
                          )
                        : MonoText(value),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The item was deleted on another device while it changed here.
class _Deletion extends StatelessWidget {
  const _Deletion({
    required this.item,
    required this.deletion,
    required this.busy,
    required this.onKeep,
    required this.onDelete,
  });

  final Item item;
  final Map<String, Object?>? deletion;
  final bool busy;
  final VoidCallback onKeep;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final when = deletion?['deleted_at'] as String?;
    final date = when == null
        ? null
        : DateFormat.yMMMd().format(DateTime.parse(when).toLocal());
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BCDialogTitle('Deleted on another device'),
        const SizedBox(height: BCSpacing.xs),
        BCDialogDescription(
          '“${item.title}” was deleted on another device'
          '${date == null ? '' : ' on $date'}, but changed here, so it was '
          'kept. Keep it, or delete it everywhere?',
        ),
        const SizedBox(height: BCSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          spacing: BCSpacing.sm,
          children: [
            BCButton(
              variant: BCButtonVariant.dangerSoft,
              isDisabled: busy,
              onPressed: onDelete,
              child: const Text('Delete everywhere'),
            ),
            BCButton(
              isDisabled: busy,
              onPressed: onKeep,
              child: const Text('Keep it'),
            ),
          ],
        ),
      ],
    );
  }
}
