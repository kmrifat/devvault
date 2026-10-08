import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vault_core/vault_core.dart';

import '../../data/vault_session.dart';
import '../../shared/desktop_ui.dart';
import '../../shared/ui.dart';
import 'conflict_resolution.dart';

/// Resolves an item changed on two devices at once, one kept version at a
/// time. Every difference needs an explicit choice; "Keep both" turns the
/// other version into an item of its own.
///
/// Desktop: a sheet (frame N05) with a radio per value. Phones: a bc_ui
/// dialog.
Future<void> showConflictDialog(BuildContext context, Item item) {
  if (DesktopTheme.maybeOf(context) != null) {
    return showDesktopSheet<void>(
      context,
      builder: (_) => ConflictDialog(itemId: item.id),
    );
  }
  return BCDialog.show<void>(
    context,
    builder: (_) => BCDialogContent(
      width: 760,
      showCloseButton: true,
      child: ConflictDialog(itemId: item.id),
    ),
  );
}

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
    final desktop = DesktopTheme.maybeOf(context) != null;

    if (conflict.versions.isEmpty) {
      return (desktop ? _DesktopDeletion.new : _Deletion.new)(
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

    if (desktop) {
      return _DesktopConflict(
        mine: mine,
        theirs: theirs,
        rows: rows,
        versions: conflict.versions.length,
        choices: _choices,
        reveal: _reveal,
        busy: _busy,
        onChoose: (key, side) => setState(() => _choices[key] = side),
        onChooseAll: chooseAll,
        onReveal: (v) => setState(() => _reveal = v),
        onKeepBoth: () => _keepBoth(mine, theirs),
        onResolve: () => _save([
          resolveConflict(mine: mine, theirs: theirs, choices: _choices),
        ]),
      );
    }

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

/// The conflict sheet (frame N05): a table with a row per difference and a
/// radio per device's value, then Keep Both, Cancel and Resolve.
class _DesktopConflict extends StatelessWidget {
  const _DesktopConflict({
    required this.mine,
    required this.theirs,
    required this.rows,
    required this.versions,
    required this.choices,
    required this.reveal,
    required this.busy,
    required this.onChoose,
    required this.onChooseAll,
    required this.onReveal,
    required this.onKeepBoth,
    required this.onResolve,
  });

  final Item mine;
  final Item theirs;
  final List<ConflictRow> rows;

  /// How many versions the conflict holds; this sheet resolves the first.
  final int versions;
  final Map<String, ConflictSide> choices;
  final bool reveal;
  final bool busy;
  final void Function(String key, ConflictSide side) onChoose;
  final ValueChanged<ConflictSide> onChooseAll;
  final ValueChanged<bool> onReveal;
  final VoidCallback onKeepBoth;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final pending = rows.where((r) => !choices.containsKey(r.key)).length;
    final noun = rows.length == 1 ? 'difference' : 'differences';
    final mineNewer = mine.rev > theirs.rev;
    String when(Item i) =>
        DateFormat.yMMMd().add_jm().format(i.updatedAt.toLocal());

    return DesktopSheet(
      width: 760,
      icon: const _ConflictTile(),
      title: 'Resolve “${mine.title}”',
      message:
          'Changed on this device and on another one at the same time. Pick '
          'the value to keep for each difference; nothing changes until you '
          'do.'
          '${versions > 1 ? ' $versions versions to go through; this is the first.' : ''}',
      leadingAction: DesktopButton(
        label: 'Keep Both',
        onPressed: busy ? null : onKeepBoth,
      ),
      actions: [
        if (busy) const DesktopProgress(semanticLabel: 'Saving'),
        DesktopButton(
          label: 'Cancel',
          onPressed: busy ? null : () => Navigator.of(context).pop(),
        ),
        DesktopButton(
          label: 'Resolve',
          kind: DesktopButtonKind.primary,
          onPressed: busy || pending > 0 ? null : onResolve,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Flexible(
            child: _ChoiceTable(
              rows: rows,
              choices: choices,
              reveal: reveal,
              headers: (
                'This device · ${when(mine)}${mineNewer ? ' · newer' : ''}',
                'Other device · ${when(theirs)}${mineNewer ? '' : ' · newer'}',
              ),
              onChoose: onChoose,
              onChooseAll: onChooseAll,
            ),
          ),
          Row(
            children: [
              if (rows.any((r) => r.secret))
                DesktopCheckbox(
                  value: reveal,
                  label: 'Show secret values',
                  onChanged: onReveal,
                ),
              const Spacer(),
              Text(
                pending == 0
                    ? rows.length == 1
                          ? 'The difference is chosen'
                          : 'All ${rows.length} $noun chosen'
                    : '$pending of ${rows.length} $noun still to choose',
                style: TextStyle(
                  fontSize: DesktopMetrics.secondarySize,
                  color: pending == 0
                      ? colors.secondaryText
                      : colors.onWarningBadge,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The conflict mark: the conflict colour on its badge tint.
class _ConflictTile extends StatelessWidget {
  const _ConflictTile();

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.conflictBadge,
          borderRadius: const BorderRadius.all(
            Radius.circular(DesktopMetrics.menuRadius + 2),
          ),
        ),
        child: SizedBox.square(
          dimension: DesktopMetrics.toolbarSearchHeight + 8,
          child: DesktopIcon(
            DesktopSymbol.conflicts,
            size: 18,
            color: colors.conflict,
          ),
        ),
      ),
    );
  }
}

/// Field | this device | other device, one row per difference, zebra
/// striped, in a rounded box. Scrolls when there are many.
class _ChoiceTable extends StatelessWidget {
  const _ChoiceTable({
    required this.rows,
    required this.choices,
    required this.reveal,
    required this.headers,
    required this.onChoose,
    required this.onChooseAll,
  });

  final List<ConflictRow> rows;
  final Map<String, ConflictSide> choices;
  final bool reveal;
  final (String, String) headers;
  final void Function(String key, ConflictSide side) onChoose;
  final ValueChanged<ConflictSide> onChooseAll;

  static const _labelWidth = DesktopMetrics.formLabelWidth;
  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final headerStyle = TextStyle(
      fontSize: DesktopMetrics.secondarySize,
      fontWeight: FontWeight.w600,
      color: colors.secondaryText,
    );
    Widget header(String text, ConflictSide side) => Row(
      children: [
        Flexible(
          child: Text(
            text,
            style: headerStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        _UseAll(side: side, onPressed: () => onChooseAll(side)),
      ],
    );
    final border = BorderSide(color: colors.innerSeparator, width: 0.5);
    const radius = BorderRadius.all(
      Radius.circular(DesktopMetrics.menuRadius + 2),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.groupBoxInner,
        border: Border.all(color: colors.groupBoxStroke, width: 0.5),
        borderRadius: radius,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.bar,
                border: Border(bottom: border),
              ),
              child: SizedBox(
                height: DesktopMetrics.tableHeaderHeight + 2,
                child: _cells([
                  Text('Field', style: headerStyle),
                  header(headers.$1, ConflictSide.mine),
                  header(headers.$2, ConflictSide.theirs),
                ]),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, row) in rows.indexed)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: i.isOdd ? colors.zebra : colors.groupBoxInner,
                          border: i == 0 ? null : Border(top: border),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: _cells([
                            Text(
                              row.label,
                              style: TextStyle(
                                fontSize: DesktopMetrics.secondarySize + 1,
                                color: colors.secondaryText,
                              ),
                            ),
                            for (final side in ConflictSide.values)
                              _DesktopChoice(
                                label:
                                    '${row.label} from '
                                    '${side == ConflictSide.mine ? 'this device' : 'the other device'}',
                                value: side == ConflictSide.mine
                                    ? row.mine
                                    : row.theirs,
                                mono: row.key.startsWith('field:'),
                                masked: row.secret && !reveal,
                                selected: choices[row.key] == side,
                                onTap: () => onChoose(row.key, side),
                              ),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The three columns: the field's name, then each device's value.
  Widget _cells(List<Widget> cells) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      spacing: _gap,
      children: [
        SizedBox(width: _labelWidth - 12 - _gap, child: cells.first),
        for (final cell in cells.skip(1)) Expanded(child: cell),
      ],
    ),
  );
}

/// A column header's link: keeps every value from that device.
class _UseAll extends StatelessWidget {
  const _UseAll({required this.side, required this.onPressed});

  final ConflictSide side;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return Semantics(
      button: true,
      label: side == ConflictSide.mine
          ? 'Keep all from this device'
          : 'Keep all from the other device',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: DesktopMetrics.tableHeaderHeight,
            ),
            child: Center(
              widthFactor: 1,
              child: Text(
                'Use All',
                style: TextStyle(
                  fontSize: DesktopMetrics.secondarySize,
                  fontWeight: FontWeight.w600,
                  color: colors.accentIcon,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One device's value for one difference: a field-like box with a radio.
/// Clicking anywhere on it keeps that value.
class _DesktopChoice extends StatelessWidget {
  const _DesktopChoice({
    required this.label,
    required this.value,
    required this.mono,
    required this.masked,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? value;
  final bool mono;
  final bool masked;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final value = this.value;
    final style = TextStyle(
      fontSize: DesktopMetrics.bodySize,
      color: colors.text,
    );
    final text = value == null
        ? Text('Not set', style: style.copyWith(color: colors.secondaryText))
        : masked
        ? Text(SecretRow.mask, style: style.copyWith(letterSpacing: 2))
        : mono
        ? Text(
            value,
            style: AppText.mono(
              context,
              fontSize: 12,
            ).copyWith(color: colors.text),
          )
        : Text(value, style: style);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected
                  ? colors.accent.withValues(alpha: 0.12)
                  : colors.field,
              border: Border.all(
                color: selected ? colors.accent : colors.fieldStroke,
                width: selected ? 1 : 0.5,
              ),
              borderRadius: const BorderRadius.all(
                Radius.circular(DesktopMetrics.fieldRadius),
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: DesktopMetrics.controlHeight + 2,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  spacing: 6,
                  children: [
                    DesktopRadio(selected: selected, onSelected: onTap),
                    Expanded(child: text),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Desktop: the item was deleted on another device while it changed here.
class _DesktopDeletion extends StatelessWidget {
  const _DesktopDeletion({
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
    return DesktopSheet(
      width: 480,
      icon: const _ConflictTile(),
      title: 'Deleted on another device',
      leadingAction: DesktopButton(
        label: 'Delete Everywhere',
        kind: DesktopButtonKind.destructive,
        onPressed: busy ? null : onDelete,
      ),
      actions: [
        DesktopButton(
          label: 'Cancel',
          onPressed: busy ? null : () => Navigator.of(context).pop(),
        ),
        DesktopButton(
          label: 'Keep It',
          kind: DesktopButtonKind.primary,
          onPressed: busy ? null : onKeep,
        ),
      ],
      child: Text(
        '“${item.title}” was deleted on another device'
        '${date == null ? '' : ' on $date'}, but changed here, so it was '
        'kept. Keep it, or delete it everywhere?',
      ),
    );
  }
}
