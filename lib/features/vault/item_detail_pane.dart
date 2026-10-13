import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart'
    show LiquidGlassAlert, LiquidGlassAlertAction, LiquidGlassAlertStyle;
import 'package:vault_core/vault_core.dart';

import '../../core/expiry.dart';
import '../../core/format.dart';
import '../../data/providers.dart';
import '../../data/vault_filter.dart';
import '../../data/vault_session.dart';

import '../../shared/ui.dart';
import '../conflict/conflict_dialog.dart';
import '../notes/notes.dart' show NoteView, copySecureNote;
import 'expiry_date_sheet.dart';
import 'vault_actions.dart';

/// Design frame I5's item detail on a phone: one item's type, place in the
/// tree, expiry with where it came from, its fields (secrets masked until
/// revealed), its files, and when it was created and changed.
class ItemDetailPane extends ConsumerWidget {
  const ItemDetailPane({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(vaultSessionProvider);
    if (session is! Unlocked) return const SizedBox.shrink();
    final item = session.index.items[itemId];
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
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
          if (item.type == ItemType.secureNote)
            _SecureNoteCard(markdown: item.notes ?? ''),
          if (item.fields.isNotEmpty)
            _Section(
              title: 'Fields',
              child: _Fields(fields: item.fields),
            ),
          if (item.attachments.isNotEmpty)
            _Section(
              title: item.attachments.length == 1 ? 'File' : 'Files',
              child: _Files(item: item, attachments: item.attachments),
            ),
          if (item.type != ItemType.secureNote)
            _Section(
              title: 'Expiry',
              child: _ExpiryCard(
                item: item,
                now: now,
                // A date the file gave is a fact; one it didn't can be set.
                onEdit:
                    item.isReadOnly || item.expiresSource == ExpirySource.file
                    ? null
                    : () => showExpiryDateSheet(context, item),
              ),
            ),
          if (item.notes case final notes?
              when notes.trim().isNotEmpty && item.type != ItemType.secureNote)
            _NotesCard(notes: notes),
          _Section(
            title: 'Details',
            child: _Details(
              item: item,
              onThisDevice: item.deviceId == thisDevice,
            ),
          ),
        ],
      ),
    );
  }
}

/// The item's tile, title and type, centred, then where it sits in the
/// tree and its tags, then its main actions as tiles (design frame I5 v2):
/// Export for a file, Copy for its first secret, Edit. The rest (Replace
/// file…, Delete item…) is behind ⋯ in the bar (`ItemScreen`).
class _Header extends ConsumerWidget {
  const _Header({required this.item, required this.app});

  final Item item;
  final AppRecord? app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bc = context.bcTheme;
    final type = item.type;
    final app = this.app;
    final place = [
      if (app != null) app.label,
      if (item.platform != null) VaultLabels.platform(item.platform),
      if (item.environment != null) VaultLabels.environment(item.environment),
    ].join(' · ');
    final file = item.attachments.firstOrNull;
    final secret = item.fields.entries.where((e) => e.value.secret).firstOrNull;

    final tiles = [
      if (file != null)
        _ActionTile(
          icon: LucideIcons.share,
          label: 'Export',
          primary: true,
          onPressed: () => exportFile(context, ref, item, file),
        ),
      if (secret != null)
        _ActionTile(
          icon: LucideIcons.copy,
          label: 'Copy',
          semanticLabel: 'Copy ${Format.fieldLabel(secret.key)}',
          primary: file == null,
          onPressed: () => copyItemField(
            context,
            ref,
            Format.fieldLabel(secret.key),
            secret.value,
          ),
        ),
      if (!item.isReadOnly)
        _ActionTile(
          icon: LucideIcons.pencil,
          label: 'Edit',
          onPressed: () => editItem(context, item),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: TypeIconTile(type: type ?? ItemType.genericFile, size: 72),
        ),
        const SizedBox(height: BCSpacing.sm + 4),
        Text(
          item.title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: BCTypography.size2xl,
            height: 1.2,
            fontWeight: BCTypography.bold,
            letterSpacing: BCTypography.trackingTight(BCTypography.size2xl),
            color: bc.foreground,
          ),
        ),
        const SizedBox(height: BCSpacing.xs + 2),
        BCText(
          type?.label ?? item.typeName,
          type: BCTextType.bodySm,
          color: BCTextColor.muted,
          align: TextAlign.center,
        ),
        if (place.isNotEmpty || item.tags.isNotEmpty) ...[
          const SizedBox(height: BCSpacing.sm + 4),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              if (place.isNotEmpty)
                BCChip(
                  variant: BCChipVariant.secondary,
                  color: BCChipColor.defaultColor,
                  startContent: app == null
                      ? null
                      : AppBadge(app: app, size: 18),
                  child: Text(place),
                ),
              for (final tag in item.tags)
                BCChip(
                  variant: BCChipVariant.secondary,
                  color: BCChipColor.defaultColor,
                  child: Text('#$tag'),
                ),
            ],
          ),
        ],
        if (tiles.isNotEmpty) ...[
          const SizedBox(height: BCSpacing.lg - 4),
          Row(
            spacing: 10,
            children: [for (final tile in tiles) Expanded(child: tile)],
          ),
        ],
      ],
    );
  }
}

/// One of the item's main actions: an icon over its name, on a tile.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.semanticLabel,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final String? semanticLabel;
  final VoidCallback onPressed;

  /// The accent tile: the action the item is mostly for.
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final shape = BCShapes.continuous(BCRadius.xxl + 2);
    final foreground = primary ? bc.accentForeground : bc.foreground;
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: BCPressable(
        onPressed: onPressed,
        shape: shape,
        background: DecoratedBox(
          decoration: ShapeDecoration(
            color: primary ? bc.accent : bc.surface,
            shape: shape,
          ),
        ),
        child: SizedBox(
          height: 68,
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 6,
            children: [
              Icon(
                icon,
                size: 20,
                color: primary ? foreground : bc.accentSoftForeground,
              ),
              BCText(
                label,
                type: BCTextType.bodySm,
                weight: BCTextWeight.semibold,
                style: TextStyle(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Copies [field] of an item through the clipboard guard: a secret comes
/// off the clipboard again (Settings: 30 s by default) and says so; a
/// plain fact stays.
Future<void> copyItemField(
  BuildContext context,
  WidgetRef ref,
  String label,
  ItemField field,
) async {
  final guard = ref.read(clipboardGuardProvider);
  if (field.secret) {
    await guard.copySecret(field.value);
  } else {
    await guard.clipboard.write(field.value);
  }
  if (!context.mounted || !field.secret) return;
  showAppToast(
    context,
    BCToastData(
      title: '$label copied',
      description:
          'Clears from the clipboard in ${guard.clearAfter.inSeconds} seconds.',
    ),
  );
}

/// The item's other actions as UIKit's action sheet (iPhone's ⋯ button):
/// Replace file… and Delete item….
Future<void> showItemMoreActions(
  BuildContext context,
  WidgetRef ref,
  Item item,
) async {
  final choice = await LiquidGlassAlert.show(
    context: context,
    title: item.title,
    style: LiquidGlassAlertStyle.actionSheet,
    actions: [
      if (!item.isReadOnly && item.attachments.isNotEmpty)
        const LiquidGlassAlertAction(id: 'replace', title: 'Replace file…'),
      const LiquidGlassAlertAction(
        id: 'delete',
        title: 'Delete item…',
        isDestructive: true,
      ),
      const LiquidGlassAlertAction(
        id: 'cancel',
        title: 'Cancel',
        isCancel: true,
      ),
    ],
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'replace':
      await replaceFile(context, item);
    case 'delete':
      await deleteItem(context, ref, item);
  }
}

/// When the item expires and how the app knows.
class _ExpiryCard extends StatelessWidget {
  const _ExpiryCard({required this.item, required this.now, this.onEdit});

  final Item item;
  final DateTime now;

  /// Opens the expiry date sheet; null when the date can't be edited here.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final expiresAt = item.expiresAt;
    final state = ExpiryState.of(item, now);
    final date = expiresAt == null
        ? ''
        : DateFormat.yMMMd().format(expiresAt.toLocal());
    final (icon, tint, soft, title, detail) = switch (state) {
      ExpiryState.none => (
        LucideIcons.calendar,
        bc.muted,
        bc.defaultColor,
        'No expiry date',
        item.attachments.isEmpty
            ? 'None was entered'
            : 'The file doesn’t state one',
      ),
      ExpiryState.valid => (
        LucideIcons.calendarCheck2,
        bc.successSoftForeground,
        bc.successSoft,
        'Valid until $date',
        '${timeLeft(expiresAt!, now)} left',
      ),
      ExpiryState.soon => (
        LucideIcons.calendarClock,
        bc.warningSoftForeground,
        bc.warningSoft,
        'Expires $date',
        '${daysLeft(expiresAt!, now)} left',
      ),
      ExpiryState.expired => (
        LucideIcons.calendarX2,
        bc.dangerSoftForeground,
        bc.dangerSoft,
        'Expired $date',
        timeAgo(expiresAt!, now),
      ),
    };

    final onEdit = this.onEdit;
    final card = _Surface(
      padding: const EdgeInsets.all(14),
      child: Row(
        spacing: 12,
        children: [
          DecoratedBox(
            decoration: ShapeDecoration(
              color: soft,
              shape: const CircleBorder(),
            ),
            child: SizedBox.square(
              dimension: 40,
              child: Icon(icon, size: 20, color: tint),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                BCText(
                  title,
                  type: BCTextType.bodySm,
                  weight: BCTextWeight.semibold,
                ),
                BCText(
                  detail,
                  type: BCTextType.bodyXs,
                  color: BCTextColor.muted,
                ),
              ],
            ),
          ),
          if (expiresAt != null) ProvenanceLabel(source: item.expiresSource),
          if (onEdit != null)
            if (expiresAt == null)
              BCButton(
                size: BCButtonSize.sm,
                variant: BCButtonVariant.ghost,
                onPressed: onEdit,
                child: const Text('Set date'),
              )
            else
              Icon(LucideIcons.chevronRight, size: 18, color: bc.muted),
        ],
      ),
    );
    if (onEdit == null || expiresAt == null) return card;
    return Semantics(
      button: true,
      label: '$title, change the date',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onEdit,
        child: card,
      ),
    );
  }
}

/// A section's name over its surface: "FIELDS", "FILE".
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Semantics(
            header: true,
            child: BCText(
              title.toUpperCase(),
              type: BCTextType.bodyXs,
              weight: BCTextWeight.semibold,
              color: BCTextColor.muted,
            ),
          ),
        ),
        child,
      ],
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
    await copyItemField(context, ref, widget.label, widget.field);
    if (!mounted) return;
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

    final name = Row(
      mainAxisSize: MainAxisSize.min,
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
        Flexible(
          child: BCText(
            widget.label,
            type: BCTextType.bodySm,
            color: BCTextColor.muted,
            maxLines: 2,
          ),
        ),
      ],
    );
    final value = Expanded(
      child: masked
          ? Align(
              alignment: AlignmentDirectional.centerStart,
              child: SecretMask(
                color: bc.foreground,
                semanticLabel: '${widget.label}, hidden',
              ),
            )
          : SelectableText(field.value, style: AppText.mono(context)),
    );
    final buttons = [
      if (field.secret)
        _IconAction(
          icon: _revealed ? LucideIcons.eyeOff : LucideIcons.eye,
          label: _revealed ? 'Hide ${widget.label}' : 'Reveal ${widget.label}',
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
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        // The name sits above the value.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 2,
          children: [
            name,
            Row(spacing: 8, children: [value, ...buttons]),
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

/// The original files, stored encrypted and exported byte for byte: the
/// whole name, its size and hash, and Export.
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
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
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
                      spacing: 4,
                      children: [
                        Text(
                          attachment.filename,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.mono(context),
                        ),
                        Text(
                          '${Format.bytes(attachment.size)} · SHA-256 '
                          '${Format.shortHash(attachment.sha256)}',
                          style: AppText.mono(
                            context,
                            fontSize: BCTypography.sizeXs,
                            color: bc.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _IconAction(
                    icon: LucideIcons.share,
                    label: 'Export ${attachment.filename}',
                    onPressed: () => exportFile(context, ref, item, attachment),
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

/// A secure note's body, rendered, with Copy (through the clipboard
/// guard, as a secret).
class _SecureNoteCard extends ConsumerWidget {
  const _SecureNoteCard({required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empty = markdown.trim().isEmpty;
    return _Surface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Row(
            children: [
              const Expanded(
                child: BCText(
                  'Note',
                  type: BCTextType.bodySm,
                  color: BCTextColor.muted,
                ),
              ),
              BCButton(
                size: BCButtonSize.sm,
                variant: BCButtonVariant.ghost,
                isDisabled: empty,
                onPressed: () => copySecureNote(context, ref, markdown),
                startContent: const Icon(LucideIcons.copy, size: 15),
                child: const Text('Copy'),
              ),
            ],
          ),
          if (empty)
            const BCText('This note is empty.', color: BCTextColor.muted)
          else
            NoteView(markdown),
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
          NoteView(notes),
        ],
      ),
    );
  }
}

/// Facts about the record: when it was created and changed, which device
/// saved it last, and that it's encrypted end to end.
class _Details extends StatelessWidget {
  const _Details({required this.item, required this.onThisDevice});

  final Item item;
  final bool onThisDevice;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final date = DateFormat.yMMMd();
    Widget row(String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        spacing: BCSpacing.sm,
        children: [
          BCText(label, color: BCTextColor.muted),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: value),
          ),
        ],
      ),
    );
    final rows = [
      row('Created', BCText(date.format(item.createdAt.toLocal()))),
      if (item.updatedAt != item.createdAt)
        row('Changed', BCText(date.format(item.updatedAt.toLocal()))),
      row(
        'Last saved on',
        BCText(onThisDevice ? 'This device' : 'Another device'),
      ),
      row(
        'Encryption',
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Icon(LucideIcons.lockKeyhole, size: 14, color: bc.success),
            const BCText('End-to-end'),
          ],
        ),
      ),
    ];
    return _Surface(
      child: Column(
        children: [
          for (final (i, r) in rows.indexed) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Divider(height: 1, thickness: 1, color: bc.separator),
              ),
            r,
          ],
        ],
      ),
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
