// Desktop UI spike: the vault screen in fluent_ui (Windows 11 look).
import 'package:fluent_ui/fluent_ui.dart';

import 'spike_data.dart';

class FluentSpikeApp extends StatelessWidget {
  const FluentSpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'DevVault',
      theme: FluentThemeData(brightness: Brightness.light),
      darkTheme: FluentThemeData(brightness: Brightness.dark),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: const _VaultWindow(),
    );
  }
}

class _VaultWindow extends StatefulWidget {
  const _VaultWindow();

  @override
  State<_VaultWindow> createState() => _VaultWindowState();
}

class _VaultWindowState extends State<_VaultWindow> {
  int _section = 0;
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final body = _VaultBody(
      selected: _selected,
      onSelect: (i) => setState(() => _selected = i),
    );
    return NavigationView(
      titleBar: const TitleBar(title: Text('DevVault')),
      pane: NavigationPane(
        selected: _section,
        onChanged: (i) => setState(() => _section = i),
        displayMode: PaneDisplayMode.expanded,
        size: const NavigationPaneSize(openWidth: 220),
        items: [
          PaneItem(
            icon: const Icon(FluentIcons.view_list),
            title: const Text('All items'),
            infoBadge: const InfoBadge(source: Text('8')),
            body: body,
          ),
          PaneItem(
            icon: const Icon(FluentIcons.clock),
            title: const Text('Expiring soon'),
            infoBadge: const InfoBadge(source: Text('2')),
            body: body,
          ),
          PaneItem(
            icon: const Icon(FluentIcons.blocked2),
            title: const Text('Expired'),
            infoBadge: const InfoBadge(source: Text('1')),
            body: body,
          ),
          PaneItemHeader(header: const Text('Apps')),
          PaneItemExpander(
            icon: const Icon(FluentIcons.app_icon_default),
            title: const Text('Kitchenly'),
            body: body,
            items: [
              PaneItem(
                icon: const Icon(FluentIcons.cell_phone),
                title: const Text('iOS'),
                body: body,
              ),
              PaneItem(
                icon: const Icon(FluentIcons.cell_phone),
                title: const Text('Android'),
                body: body,
              ),
            ],
          ),
          PaneItem(
            icon: const Icon(FluentIcons.app_icon_default),
            title: const Text('Ledgerly'),
            body: body,
          ),
        ],
        footerItems: [
          PaneItem(
            icon: const Icon(FluentIcons.settings),
            title: const Text('Settings'),
            body: body,
          ),
        ],
      ),
    );
  }
}

class _VaultBody extends StatelessWidget {
  const _VaultBody({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return ScaffoldPage(
      padding: EdgeInsets.zero,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Row(
          children: [
            Text('All items', style: theme.typography.subtitle),
            const SizedBox(width: 16),
            const SizedBox(
              width: 280,
              child: TextBox(
                placeholder: 'Search',
                prefix: Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(FluentIcons.search, size: 12),
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 260,
              child: CommandBar(
                mainAxisAlignment: MainAxisAlignment.end,
                primaryItems: [
                  CommandBarButton(
                    icon: const Icon(FluentIcons.import),
                    label: const Text('Import'),
                    onPressed: () {},
                  ),
                  CommandBarButton(
                    icon: const Icon(FluentIcons.add),
                    label: const Text('New'),
                    onPressed: () {},
                  ),
                  CommandBarButton(
                    icon: const Icon(FluentIcons.lock),
                    label: const Text('Lock'),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 340,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: spikeItems.length,
              itemBuilder: (context, i) {
                final item = spikeItems[i];
                return ListTile.selectable(
                  selected: i == selected,
                  onSelectionChange: (_) => onSelect(i),
                  leading: Icon(
                    item.file == null ? FluentIcons.lock : FluentIcons.document,
                    size: 16,
                  ),
                  title: Text(item.title),
                  subtitle: Text('${item.type} · ${item.app}'),
                  trailing: item.expiry == null
                      ? null
                      : Text(item.expiry!, style: theme.typography.caption),
                );
              },
            ),
          ),
          Container(width: 1, color: theme.resources.dividerStrokeColorDefault),
          Expanded(child: _Inspector(item: spikeItems[selected])),
        ],
      ),
    );
  }
}

class _Inspector extends StatefulWidget {
  const _Inspector({required this.item});

  final SpikeItem item;

  @override
  State<_Inspector> createState() => _InspectorState();
}

class _InspectorState extends State<_Inspector> {
  String? _platform;
  String? _environment;
  bool _remind = true;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final item = widget.item;
    final platform = _platform ?? item.platform;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(item.title, style: theme.typography.title),
        Text(item.type, style: theme.typography.body),
        const SizedBox(height: 16),
        InfoLabel(
          label: 'Name',
          child: TextBox(controller: TextEditingController(text: item.title)),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              // Suggestions, or type your own.
              child: InfoLabel(
                label: 'Platform',
                child: EditableComboBox<String>(
                  value: platform,
                  isExpanded: true,
                  items: [
                    for (final p in {...spikePlatforms, platform})
                      ComboBoxItem(value: p, child: Text(p)),
                  ],
                  onChanged: (v) => setState(() => _platform = v),
                  onFieldSubmitted: (text) {
                    setState(() => _platform = text);
                    return text;
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InfoLabel(
                label: 'Environment',
                child: ComboBox<String>(
                  value: _environment ?? item.environment,
                  isExpanded: true,
                  items: [
                    for (final e in spikeEnvironments)
                      ComboBoxItem(value: e, child: Text(e)),
                  ],
                  onChanged: (v) => setState(() => _environment = v),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        InfoLabel(
          label: 'Store password',
          child: PasswordBox(
            placeholder: '••••••••••',
            revealMode: PasswordRevealMode.peek,
          ),
        ),
        const SizedBox(height: 12),
        if (item.file case final file?)
          InfoLabel(label: 'File', child: Text(file)),
        const SizedBox(height: 12),
        InfoLabel(
          label: 'Expires',
          child: Text(item.expiry ?? 'No expiry date'),
        ),
        const SizedBox(height: 12),
        ToggleSwitch(
          checked: _remind,
          onChanged: (v) => setState(() => _remind = v),
          content: const Text('Remind me before it expires'),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Button(onPressed: () {}, child: const Text('Export…')),
            const SizedBox(width: 8),
            FilledButton(onPressed: () {}, child: const Text('Save')),
          ],
        ),
      ],
    );
  }
}
