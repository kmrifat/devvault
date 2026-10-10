import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_core/vault_core.dart';

import '../../data/vault_filter.dart';
import '../../data/vault_session.dart';
import '../../shared/desktop_ui.dart';
import 'vault_actions.dart';

/// An item's context menu, in the sidebar tree and the list: edit it, move
/// it to another app, delete it. An item this version can't write offers
/// only Delete.
List<DesktopMenuAction> itemMenu(
  BuildContext context,
  WidgetRef ref,
  Item item,
) => [
  if (!item.isReadOnly) ...[
    DesktopMenuAction('Edit item…', () => editItem(context, item)),
    DesktopMenuAction('Move to app…', () => moveItemTo(context, ref, item)),
  ],
  DesktopMenuAction(
    'Delete item…',
    () => deleteItem(context, ref, item),
    destructive: true,
    startsGroup: true,
  ),
];

/// Asks which app [item] goes in ("No app" included), then moves it there,
/// keeping its platform and environment: what dragging it onto an app
/// does, for the keyboard.
Future<void> moveItemTo(BuildContext context, WidgetRef ref, Item item) async {
  final session = ref.read(vaultSessionProvider);
  if (session is! Unlocked) return;
  final index = session.index;
  final current = index.apps.containsKey(item.appId)
      ? item.appId!
      : VaultFilter.none;
  final apps = index.apps.values.toList()
    ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  final app = await _choose(
    context,
    title: 'Move “${item.title}”',
    label: 'App',
    current: current,
    choices: [
      const DesktopChoice(VaultFilter.none, 'No app'),
      for (final app in apps) DesktopChoice(app.id, app.label),
    ],
  );
  if (app == null || app == current || !context.mounted) return;
  await moveItem(context, ref, item, TreePlace(app: app));
}

/// Asks which organization [app] belongs to ("Personal" for none), then
/// moves it there: what dragging it onto an organization does, for the
/// keyboard.
Future<void> moveAppTo(
  BuildContext context,
  WidgetRef ref,
  AppRecord app,
) async {
  final session = ref.read(vaultSessionProvider);
  if (session is! Unlocked) return;
  const personal = '';
  final org = await _choose(
    context,
    title: 'Move “${app.name}”',
    label: 'Organization',
    current: app.organization ?? personal,
    choices: [
      const DesktopChoice(personal, 'Personal (no organization)'),
      for (final org in session.index.organizations) DesktopChoice(org, org),
    ],
  );
  if (org == null || !context.mounted) return;
  await moveApp(context, ref, app, org == personal ? null : org);
}

Future<String?> _choose(
  BuildContext context, {
  required String title,
  required String label,
  required String current,
  required List<DesktopChoice<String>> choices,
}) => showDesktopSheet<String>(
  context,
  builder: (_) => _ChooseSheet(
    title: title,
    label: label,
    current: current,
    choices: choices,
  ),
);

class _ChooseSheet extends StatefulWidget {
  const _ChooseSheet({
    required this.title,
    required this.label,
    required this.current,
    required this.choices,
  });

  final String title;
  final String label;
  final String current;
  final List<DesktopChoice<String>> choices;

  @override
  State<_ChooseSheet> createState() => _ChooseSheetState();
}

class _ChooseSheetState extends State<_ChooseSheet> {
  late String _value = widget.current;

  @override
  Widget build(BuildContext context) {
    return DesktopSheet(
      title: widget.title,
      width: 440,
      actions: [
        DesktopButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        DesktopButton(
          label: 'Move',
          kind: DesktopButtonKind.primary,
          onPressed: _value == widget.current
              ? null
              : () => Navigator.of(context).pop(_value),
        ),
      ],
      child: DesktopForm(
        children: [
          DesktopFormRow(
            label: widget.label,
            child: DesktopPopup<String>(
              value: _value,
              choices: widget.choices,
              onChanged: (v) => setState(() => _value = v),
            ),
          ),
        ],
      ),
    );
  }
}
