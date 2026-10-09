import 'dart:async';

import 'package:flutter/material.dart'
    show Material, MaterialType, SelectableText, Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vault_core/vault_core.dart';

import '../../core/expiry.dart';
import '../../core/format.dart';
import '../../data/providers.dart';
import '../../data/vault_filter.dart';
import '../../data/vault_session.dart';
import '../../shared/desktop_ui.dart';
import '../../shared/ui.dart' show BCToastData, showAppToast;
import '../../shared/widgets/mono_text.dart';
import '../../shared/widgets/provenance_label.dart';
import '../../shared/widgets/secret_row.dart' show SecretRow;
import '../conflict/conflict_dialog.dart';
import '../notes/notes.dart' show NoteView;
import 'desktop_item_type.dart';
import 'vault_actions.dart';

/// When [item] was created and last changed, and where: the line the
/// window's status bar shows for the selected item.
String itemHistory(Item item, {required bool onThisDevice}) {
  final date = DateFormat.yMMMd();
  final updated = item.updatedAt == item.createdAt
      ? ''
      : ' · Updated ${date.format(item.updatedAt.toLocal())}';
  return 'Created ${date.format(item.createdAt.toLocal())}$updated'
      '${onThisDevice ? ' on this device' : ' on another device'}';
}

/// Design frame N03's inspector: the selected item's type, name and place,
/// Export / Edit / ⋯, its expiry and where that date came from, its fields
/// (secrets masked until revealed, copied through the clipboard guard),
/// its files, notes and tags. When it was made and changed is in the
/// window's status bar.
///
/// Phones show items with `ItemDetailPane` instead.
class DesktopInspector extends ConsumerWidget {
  const DesktopInspector({super.key, required this.itemId});

  /// The selected item, or null when nothing is selected.
  final String? itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(vaultSessionProvider);
    if (session is! Unlocked) return const SizedBox.shrink();
    final id = itemId;
    if (id == null) {
      return const _Placeholder(
        title: 'No item selected',
        description: 'Pick an item to see its fields and files.',
      );
    }
    final item = session.index.items[id];
    if (item == null) {
      return const _Placeholder(
        title: 'This item isn’t in the vault',
        description: 'It may have been deleted on this or another device.',
      );
    }
    final now = ref.watch(clockProvider)();

    // Material for the kits' button ink and the selectable values.
    return Material(
      type: MaterialType.transparency,
      child: SingleChildScrollView(
        // Keyed by item, so revealed secrets are hidden again on the next one.
        key: ValueKey(item.id),
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            _Header(item: item, app: session.index.apps[item.appId]),
            if (item.isReadOnly)
              const _Notice(
                symbol: DesktopSymbol.lock,
                conflict: false,
                text:
                    'Saved by a newer version of DevVault. You can view and '
                    'export it here, but not change it.',
              ),
            if (item.conflict != null)
              _Notice(
                symbol: DesktopSymbol.conflicts,
                conflict: true,
                text: Conflict.of(item).versions.isEmpty
                    ? 'Deleted on another device while it changed here. It '
                          'was kept until you choose.'
                    : 'Another device changed this item at the same time. '
                          'Both versions are kept until you choose.',
                action: DesktopButton(
                  label: 'Resolve…',
                  onPressed: () => showConflictDialog(context, item),
                ),
              ),
            _ExpiryBox(item: item, now: now),
            if (item.fields.isNotEmpty)
              _Section(
                title: 'Fields',
                child: _Box(
                  children: [
                    for (final MapEntry(:key, :value) in item.fields.entries)
                      _FieldRow(label: Format.fieldLabel(key), field: value),
                  ],
                ),
              ),
            if (item.attachments.isNotEmpty)
              _Section(
                title: item.attachments.length == 1 ? 'File' : 'Files',
                child: _Box(
                  children: [
                    for (final attachment in item.attachments)
                      _FileRow(
                        item: item,
                        attachment: attachment,
                        canReplace:
                            !item.isReadOnly && item.attachments.length == 1,
                      ),
                  ],
                ),
              ),
            if (item.notes case final notes? when notes.trim().isNotEmpty)
              _Section(title: 'Notes', child: NoteView(notes)),
            if (item.tags.isNotEmpty)
              _Section(
                title: 'Tags',
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final tag in item.tags) _Tag(tag)],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What the inspector says when there's no item to show.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DesktopMetrics.bodySize,
                fontWeight: FontWeight.w600,
                color: colors.secondaryText,
              ),
            ),
            Text(
              description,
              textAlign: TextAlign.center,
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

/// The type tile, name and "Type · App › Platform › Environment", then
/// Export, Edit and ⋯ (Replace file…, Delete item…).
class _Header extends ConsumerWidget {
  const _Header({required this.item, required this.app});

  final Item item;
  final AppRecord? app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.desktopColors;
    final app = this.app;
    final place = [
      if (app != null) app.label,
      if (item.platform != null) VaultLabels.platform(item.platform),
      if (item.environment != null) VaultLabels.environment(item.environment),
    ].join(' › ');
    final path = place.isEmpty ? item.typeLabel : '${item.typeLabel} · $place';
    final file = item.attachments.firstOrNull;

    // Each button its own node, so screen readers (and tests) find it by
    // its label alone.
    Widget button(Widget child) => Semantics(container: true, child: child);

    return Row(
      spacing: 12,
      children: [
        DesktopTypeTile(type: item.type, semanticLabel: item.typeLabel),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: DesktopMetrics.inspectorTitleSize,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  color: colors.text,
                ),
              ),
              Text(
                path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: DesktopMetrics.labelSize,
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
        ),
        if (file != null)
          button(
            DesktopButton(
              label: 'Export',
              onPressed: () => exportFile(context, ref, item, file),
            ),
          ),
        if (!item.isReadOnly)
          button(
            DesktopButton(
              label: 'Edit',
              onPressed: () => editItem(context, item),
            ),
          ),
        DesktopPullDownButton(
          label: 'More actions',
          actions: [
            if (!item.isReadOnly && item.attachments.isNotEmpty)
              DesktopMenuAction(
                'Replace file…',
                () => replaceFile(context, item),
              ),
            DesktopMenuAction(
              'Delete item…',
              () => deleteItem(context, ref, item),
              destructive: true,
            ),
          ],
        ),
      ],
    );
  }
}

/// A read-only or conflict notice, with an optional button (Resolve…).
class _Notice extends StatelessWidget {
  const _Notice({
    required this.symbol,
    required this.conflict,
    required this.text,
    this.action,
  });

  final DesktopSymbol symbol;

  /// Drawn in the conflict colours; otherwise the warning ones.
  final bool conflict;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final foreground = conflict
        ? colors.onConflictBadge
        : colors.onWarningBadge;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: conflict ? colors.conflictBadge : colors.warningBadge,
        borderRadius: const BorderRadius.all(
          Radius.circular(DesktopMetrics.menuRadius + 2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          spacing: 10,
          children: [
            DesktopIcon(symbol, size: 14, color: foreground),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: DesktopMetrics.labelSize,
                  color: foreground,
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

/// When the item expires, how long that is from now, where the date came
/// from (said in words and on a pill).
class _ExpiryBox extends StatelessWidget {
  const _ExpiryBox({required this.item, required this.now});

  final Item item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final expiresAt = item.expiresAt;
    final date = expiresAt == null
        ? ''
        : DateFormat.yMMMd().format(expiresAt.toLocal());
    final (tint, title) = switch (ExpiryState.of(item, now)) {
      ExpiryState.none => (colors.secondaryText, 'No expiry date'),
      ExpiryState.valid => (
        colors.success,
        'Valid until $date · ${timeLeft(expiresAt!, now)} left',
      ),
      ExpiryState.soon => (
        colors.warning,
        'Expires $date · ${daysLeft(expiresAt!, now)} left',
      ),
      ExpiryState.expired => (
        colors.danger,
        'Expired $date · ${timeAgo(expiresAt!, now)}',
      ),
    };
    final explanation = switch (item.expiresSource) {
      ExpirySource.file => 'Read from the file itself.',
      ExpirySource.user => 'Entered by you.',
      null => 'Nothing in the file says when it expires.',
    };

    return DesktopGroupBox(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        spacing: 10,
        children: [
          DesktopIcon(DesktopSymbol.calendar, size: 16, color: tint),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 1,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: DesktopMetrics.bodySize,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                Text(
                  explanation,
                  style: TextStyle(
                    fontSize: DesktopMetrics.secondarySize,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          if (expiresAt != null) _SourcePill(source: item.expiresSource),
        ],
      ),
    );
  }
}

/// Where the expiry came from, as a pill: "From file", "Set by you".
class _SourcePill extends StatelessWidget {
  const _SourcePill({required this.source});

  final ExpirySource? source;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final symbol = switch (source) {
      ExpirySource.file => DesktopSymbol.typeFile,
      ExpirySource.user => DesktopSymbol.person,
      null => null,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.groupBoxInner,
        border: Border.all(color: colors.fieldStroke, width: 0.5),
        borderRadius: const BorderRadius.all(
          Radius.circular(DesktopMetrics.tokenRadius),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            if (symbol != null)
              DesktopIcon(symbol, size: 11, color: colors.secondaryText),
            Text(
              ProvenanceLabel.textFor(source),
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

/// A titled part of the inspector: Fields, File, Notes, Tags.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 7,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: TextStyle(
              fontSize: DesktopMetrics.secondarySize,
              fontWeight: FontWeight.w600,
              color: context.desktopColors.secondaryText,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// The box that holds the field and file rows: the inner group-box fill,
/// with a hairline between rows.
class _Box extends StatelessWidget {
  const _Box({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0)
                SizedBox(
                  height: 0.5,
                  child: ColoredBox(color: colors.innerSeparator),
                ),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

/// One field: a dot for where it came from (accent: the file; grey: typed
/// in), its name, the value in mono with secrets masked, then reveal (for
/// secrets) and copy. Everything is copied through the clipboard guard.
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
      showAppToast(
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
    final colors = context.desktopColors;
    final field = widget.field;
    final fromFile = field.source == FieldSource.file;
    final masked = field.secret && !_revealed;
    final valueStyle = TextStyle(
      fontFamily: AppText.monoFamily,
      fontSize: DesktopMetrics.labelSize,
      height: 1.4,
      color: colors.text,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: DesktopMetrics.inspectorFieldRowHeight,
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 4, top: 2, bottom: 2),
        child: Row(
          spacing: 8,
          children: [
            SizedBox(
              width: 132,
              child: Row(
                spacing: 6,
                children: [
                  Tooltip(
                    message: fromFile ? 'From the file' : 'Entered by you',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: fromFile
                            ? colors.accentIcon
                            : colors.tertiaryText,
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox.square(dimension: 5),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DesktopMetrics.labelSize,
                        color: colors.secondaryText,
                      ),
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
                        style: valueStyle.copyWith(letterSpacing: 1),
                      ),
                    )
                  : SelectableText(field.value, style: valueStyle),
            ),
            if (field.secret)
              DesktopIconButton(
                symbol: _revealed
                    ? DesktopSymbol.conceal
                    : DesktopSymbol.reveal,
                tooltip: _revealed
                    ? 'Hide ${widget.label}'
                    : 'Reveal ${widget.label}',
                size: 14,
                onPressed: () => setState(() => _revealed = !_revealed),
              ),
            if (_copied)
              SizedBox(
                width: DesktopMetrics.toolbarSearchHeight * 2,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 3,
                  children: [
                    DesktopIcon(
                      DesktopSymbol.check,
                      size: 11,
                      color: colors.success,
                    ),
                    Text(
                      'Copied',
                      style: TextStyle(
                        fontSize: DesktopMetrics.secondarySize,
                        color: colors.text,
                      ),
                    ),
                  ],
                ),
              )
            else
              DesktopIconButton(
                symbol: DesktopSymbol.copy,
                tooltip: 'Copy ${widget.label}',
                size: 14,
                onPressed: _copy,
              ),
          ],
        ),
      ),
    );
  }
}

/// One of the item's files, stored encrypted and exported byte for byte:
/// its name, size and hash, Save As… and (for a single file) Replace….
class _FileRow extends ConsumerWidget {
  const _FileRow({
    required this.item,
    required this.attachment,
    required this.canReplace,
  });

  final Item item;
  final Attachment attachment;
  final bool canReplace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.desktopColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      child: Row(
        spacing: 10,
        children: [
          DesktopIcon(
            DesktopSymbol.typeFile,
            size: 18,
            color: colors.secondaryText,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 1,
              children: [
                MonoText(
                  attachment.filename,
                  middleEllipsis: true,
                  style: TextStyle(
                    fontSize: DesktopMetrics.labelSize,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                Text(
                  '${Format.bytes(attachment.size)} · sha256 '
                  '${Format.shortHash(attachment.sha256)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: DesktopMetrics.secondarySize,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          Semantics(
            container: true,
            child: DesktopButton(
              label: 'Save As…',
              onPressed: () => exportFile(context, ref, item, attachment),
            ),
          ),
          if (canReplace)
            Semantics(
              container: true,
              child: DesktopButton(
                label: 'Replace…',
                onPressed: () => replaceFile(context, item),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.tag);

  final String tag;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.groupBox,
        border: Border.all(color: colors.groupBoxStroke, width: 0.5),
        borderRadius: const BorderRadius.all(
          Radius.circular(DesktopMetrics.tokenRadius),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          '#$tag',
          style: TextStyle(
            fontSize: DesktopMetrics.secondarySize,
            color: colors.text,
          ),
        ),
      ),
    );
  }
}
