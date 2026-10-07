import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vault_core/vault_core.dart';

import '../../core/expiry.dart';
import '../../core/format.dart';
import '../../data/providers.dart';
import '../../data/vault_filter.dart';
import '../../data/vault_session.dart';
import '../../shared/ui.dart';
import '../conflict/conflict_dialog.dart';
import 'vault_actions.dart';

/// Design frame D03's detail pane: one item's type, place in the tree,
/// expiry with where it came from, its fields (secrets masked until
/// revealed), its files, and when it was created and changed.
class ItemDetailPane extends ConsumerWidget {
  const ItemDetailPane({super.key, required this.itemId});

  /// The selected item, or null when nothing is selected.
  final String? itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(vaultSessionProvider);
    if (session is! Unlocked) return const SizedBox.shrink();
    final id = itemId;
    if (id == null) {
      return const Center(
        child: BCEmptyState(
          icon: Icon(LucideIcons.fileKey2),
          title: 'No item selected',
          description: 'Pick an item to see its fields and files.',
        ),
      );
    }
    final item = session.index.items[id];
    if (item == null) {
      return const Center(
        child: BCEmptyState(
          icon: Icon(LucideIcons.fileQuestion),
          title: 'This item isn’t in the vault',
          description: 'It may have been deleted on this or another device.',
        ),
      );
    }
    final now = ref.watch(clockProvider)();
    final thisDevice = ref.watch(deviceIdProvider);

    return SingleChildScrollView(
      // Keyed by item, so revealed secrets are hidden again on the next one.
      key: ValueKey(item.id),
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 18,
        children: [
          _Header(item: item, app: session.index.apps[item.appId]),
          if (item.isReadOnly)
            const _Notice(
              icon: LucideIcons.lock,
              text:
                  'Saved by a newer version of DevVault. You can view and '
                  'export it here, but not change it.',
            ),
          if (item.conflict != null)
            _Notice(
              icon: LucideIcons.gitMerge,
              text: Conflict.of(item).versions.isEmpty
                  ? 'Deleted on another device while it changed here. It '
                        'was kept until you choose.'
                  : 'Another device changed this item at the same time. '
                        'Both versions are kept until you choose.',
              action: BCButton(
                size: BCButtonSize.sm,
                onPressed: () => showConflictDialog(context, item),
                child: const Text('Resolve…'),
              ),
            ),
          _ExpiryCard(item: item, now: now),
          if (item.fields.isNotEmpty) _Fields(fields: item.fields),
          if (item.attachments.isNotEmpty)
            _Files(item: item, attachments: item.attachments),
          if (item.notes case final notes? when notes.trim().isNotEmpty)
            _NotesCard(notes: notes),
          _Meta(item: item, onThisDevice: item.deviceId == thisDevice),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.item, required this.app});

  final Item item;
  final AppRecord? app;

  static BCChipColor _typeColor(ItemType? type) => switch (type) {
    ItemType.androidKeystore => BCChipColor.success,
    ItemType.firebaseConfig => BCChipColor.warning,
    ItemType.appleAuthKey || ItemType.gcpServiceAccount => BCChipColor.accent,
    _ => BCChipColor.defaultColor,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bc = context.bcTheme;
    final type = item.type;
    final app = this.app;
    final place = [
      if (app != null) app.name,
      if (item.platform != null) VaultLabels.platform(item.platform),
      if (item.environment != null) VaultLabels.environment(item.environment),
    ].join(' · ');
    final file = item.attachments.firstOrNull;

    return Row(
      spacing: 16,
      children: [
        TypeIconTile(type: type ?? ItemType.genericFile, size: 56),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 24,
                  height: 1.2,
                  fontWeight: BCTypography.semiBold,
                  color: bc.foreground,
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  BCChip(
                    size: BCChipSize.sm,
                    variant: BCChipVariant.soft,
                    color: _typeColor(type),
                    child: Text(type?.label ?? item.typeName),
                  ),
                  if (place.isNotEmpty)
                    BCChip(
                      size: BCChipSize.sm,
                      variant: BCChipVariant.secondary,
                      color: BCChipColor.defaultColor,
                      startContent: app == null
                          ? null
                          : DecoratedBox(
                              decoration: ShapeDecoration(
                                color: AppBadge.colorFor(app),
                                shape: BCShapes.continuous(3),
                              ),
                              child: const SizedBox.square(dimension: 10),
                            ),
                      child: Text(place),
                    ),
                  for (final tag in item.tags)
                    BCChip(
                      size: BCChipSize.sm,
                      variant: BCChipVariant.tertiary,
                      color: BCChipColor.defaultColor,
                      child: Text('#$tag'),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (file != null)
          BCButton(
            size: BCButtonSize.sm,
            onPressed: () => exportFile(context, ref, item, file),
            startContent: const Icon(LucideIcons.share, size: 15),
            child: const Text('Export'),
          ),
        if (!item.isReadOnly)
          BCButton(
            size: BCButtonSize.sm,
            variant: BCButtonVariant.secondary,
            isIconOnly: true,
            onPressed: () => editItem(context, item),
            child: const Icon(
              LucideIcons.pencil,
              size: 16,
              semanticLabel: 'Edit',
            ),
          ),
        BCMenu(
          alignment: BCOverlayAlignment.end,
          trigger: (context, controller) => BCButton(
            size: BCButtonSize.sm,
            variant: BCButtonVariant.secondary,
            isIconOnly: true,
            onPressed: controller.toggle,
            child: const Icon(
              LucideIcons.ellipsis,
              size: 16,
              semanticLabel: 'More actions',
            ),
          ),
          children: [
            BCMenuItem(
              title: 'Delete item…',
              icon: const Icon(LucideIcons.trash2),
              variant: BCMenuItemVariant.danger,
              onSelected: () => deleteItem(context, ref, item),
            ),
          ],
        ),
      ],
    );
  }
}

/// When the item expires and how the app knows.
class _ExpiryCard extends StatelessWidget {
  const _ExpiryCard({required this.item, required this.now});

  final Item item;
  final DateTime now;

  static String _span(Duration d) {
    final days = d.inDays.abs();
    if (days >= 730) return '${days ~/ 365} years';
    if (days >= 60) return '${days ~/ 30} months';
    return days == 1 ? '1 day' : '$days days';
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final expiresAt = item.expiresAt;
    final state = ExpiryState.of(item, now);
    final date = expiresAt == null
        ? ''
        : DateFormat.yMMMd().format(expiresAt.toLocal());
    final (icon, tint, title, detail) = switch (state) {
      ExpiryState.none => (
        LucideIcons.calendar,
        bc.muted,
        'No expiry date',
        null,
      ),
      ExpiryState.valid => (
        LucideIcons.calendarCheck2,
        bc.success,
        'Valid until $date',
        '${_span(expiresAt!.difference(now))} left',
      ),
      ExpiryState.soon => (
        LucideIcons.calendarClock,
        bc.warning,
        'Expires $date',
        '${daysLeft(expiresAt!, now)} left',
      ),
      ExpiryState.expired => (
        LucideIcons.calendarX2,
        bc.danger,
        'Expired $date',
        '${_span(now.difference(expiresAt!))} ago',
      ),
    };
    final explanation = switch (item.expiresSource) {
      ExpirySource.file => 'Read from the file itself.',
      ExpirySource.user => 'Entered by you.',
      null => 'Nothing in the file says when it expires.',
    };

    return _Surface(
      padding: const EdgeInsets.all(16),
      child: Row(
        spacing: 14,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: bc.defaultColor,
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(
              dimension: 40,
              child: Icon(icon, size: 19, color: tint),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                Text.rich(
                  TextSpan(
                    text: title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: BCTypography.semiBold,
                      color: bc.foreground,
                    ),
                    children: [
                      if (detail != null)
                        TextSpan(
                          text: '  ·  $detail',
                          style: BCTypography.textSm.copyWith(
                            fontWeight: BCTypography.regular,
                            color: bc.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                BCText(
                  explanation,
                  type: BCTextType.bodySm,
                  color: BCTextColor.muted,
                ),
              ],
            ),
          ),
          if (expiresAt != null) ProvenanceLabel(source: item.expiresSource),
        ],
      ),
    );
  }
}

/// The item's fields: a dot for where each came from (accent: the file,
/// plain: typed in), the value in mono, secrets masked.
class _Fields extends StatelessWidget {
  const _Fields({required this.fields});

  final Map<String, ItemField> fields;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final entries = fields.entries.toList();
    return _Surface(
      child: Column(
        children: [
          for (final (i, MapEntry(:key, :value)) in entries.indexed) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Divider(height: 1, thickness: 1, color: bc.separator),
              ),
            _FieldRow(label: Format.fieldLabel(key), field: value),
          ],
        ],
      ),
    );
  }
}

class _FieldRow extends ConsumerStatefulWidget {
  const _FieldRow({required this.label, required this.field});

  final String label;
  final ItemField field;

  @override
  ConsumerState<_FieldRow> createState() => _FieldRowState();
}

class _FieldRowState extends ConsumerState<_FieldRow> {
  bool _revealed = false;
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final guard = ref.read(clipboardGuardProvider);
    final value = widget.field.value;
    // Secrets come off the clipboard again (Settings: 30 s by default);
    // plain facts stay.
    if (widget.field.secret) {
      await guard.copySecret(value);
    } else {
      await guard.clipboard.write(value);
    }
    if (!mounted) return;
    if (widget.field.secret) {
      BCToast.show(
        context,
        BCToastData(
          title: '${widget.label} copied',
          description:
              'Clears from the clipboard in '
              '${guard.clearAfter.inSeconds} seconds.',
        ),
      );
    }
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final field = widget.field;
    final fromFile = field.source == FieldSource.file;
    final masked = field.secret && !_revealed;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          spacing: 16,
          children: [
            SizedBox(
              width: 140,
              child: Row(
                spacing: 8,
                children: [
                  Tooltip(
                    message: fromFile ? 'From the file' : 'Entered by you',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: fromFile ? bc.accent : bc.foreground,
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox.square(dimension: 6),
                    ),
                  ),
                  Expanded(
                    child: BCText(
                      widget.label,
                      type: BCTextType.bodySm,
                      color: BCTextColor.muted,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: masked
                  ? Semantics(
                      label: '${widget.label}, hidden',
                      excludeSemantics: true,
                      child: Text(
                        SecretRow.mask,
                        style: TextStyle(
                          color: bc.foreground,
                          letterSpacing: 2,
                        ),
                      ),
                    )
                  : SelectableText(field.value, style: AppText.mono(context)),
            ),
            if (field.secret)
              _IconAction(
                icon: _revealed ? LucideIcons.eyeOff : LucideIcons.eye,
                label: _revealed
                    ? 'Hide ${widget.label}'
                    : 'Reveal ${widget.label}',
                onPressed: () => setState(() => _revealed = !_revealed),
              ),
            if (_copied)
              const BCChip(
                size: BCChipSize.sm,
                variant: BCChipVariant.soft,
                color: BCChipColor.success,
                startContent: Icon(LucideIcons.check, size: 12),
                child: Text('Copied'),
              )
            else
              _IconAction(
                icon: LucideIcons.copy,
                label: 'Copy ${widget.label}',
                onPressed: _copy,
              ),
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return BCButton(
      variant: BCButtonVariant.ghost,
      size: BCButtonSize.sm,
      isIconOnly: true,
      onPressed: onPressed,
      child: Icon(icon, size: 16, semanticLabel: label),
    );
  }
}

/// The original files, stored encrypted and exported byte for byte.
class _Files extends ConsumerWidget {
  const _Files({required this.item, required this.attachments});

  final Item item;
  final List<Attachment> attachments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bc = context.bcTheme;
    return _Surface(
      child: Column(
        children: [
          for (final (i, attachment) in attachments.indexed) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 66),
                child: Divider(height: 1, thickness: 1, color: bc.separator),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                spacing: 12,
                children: [
                  DecoratedBox(
                    decoration: ShapeDecoration(
                      color: bc.defaultColor,
                      shape: BCShapes.continuous(BCRadius.xl),
                    ),
                    child: SizedBox.square(
                      dimension: 40,
                      child: Icon(
                        LucideIcons.fileLock2,
                        size: 20,
                        color: bc.foreground,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 3,
                      children: [
                        MonoText(attachment.filename, middleEllipsis: true),
                        BCText(
                          '${Format.bytes(attachment.size)} · sha256 '
                          '${Format.shortHash(attachment.sha256)}',
                          type: BCTextType.bodyXs,
                          color: BCTextColor.muted,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  BCButton(
                    size: BCButtonSize.sm,
                    variant: BCButtonVariant.tertiary,
                    onPressed: () => exportFile(context, ref, item, attachment),
                    startContent: const Icon(LucideIcons.download, size: 14),
                    child: const Text('Save as…'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          const BCText(
            'Notes',
            type: BCTextType.bodySm,
            color: BCTextColor.muted,
          ),
          SelectableText(notes),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.item, required this.onThisDevice});

  final Item item;
  final bool onThisDevice;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final date = DateFormat.yMMMd();
    final updated = item.updatedAt == item.createdAt
        ? ''
        : ' · Updated ${date.format(item.updatedAt.toLocal())}';
    return Row(
      spacing: 16,
      children: [
        Expanded(
          child: BCText(
            'Created ${date.format(item.createdAt.toLocal())}$updated'
            '${onThisDevice ? ' on this device' : ' on another device'}',
            type: BCTextType.bodyXs,
            color: BCTextColor.muted,
          ),
        ),
        Row(
          spacing: 6,
          children: [
            Icon(LucideIcons.lockKeyhole, size: 13, color: bc.muted),
            const BCText(
              'End-to-end encrypted',
              type: BCTextType.bodyXs,
              color: BCTextColor.muted,
            ),
          ],
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;

  /// A button at the end, such as "Resolve…".
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: bc.warningSoft,
        shape: BCShapes.continuous(BCRadius.xxl),
      ),
      child: Padding(
        padding: const EdgeInsets.all(BCSpacing.md),
        child: Row(
          spacing: BCSpacing.sm,
          children: [
            Icon(icon, size: 17, color: bc.warning),
            Expanded(
              child: Text(
                text,
                style: BCTypography.textSm.copyWith(
                  color: bc.warningSoftForeground,
                ),
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// A rounded surface like bc_ui's list group, clipped so rows' highlights
/// follow the corners.
class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final shape = BCShapes.continuous(BCRadius.xxxl);
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: context.bcTheme.surface,
          shape: shape,
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
