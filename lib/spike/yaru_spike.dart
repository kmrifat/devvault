// Desktop UI spike: the vault screen in yaru (Ubuntu / GNOME look).
import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import 'spike_data.dart';

class YaruSpikeApp extends StatelessWidget {
  const YaruSpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return YaruTheme(
      builder: (context, yaru, child) => MaterialApp(
        title: 'DevVault',
        theme: yaru.theme,
        darkTheme: yaru.darkTheme,
        debugShowCheckedModeBanner: false,
        home: const _VaultWindow(),
      ),
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

  static const _sections = [
    (Icons.layers_outlined, 'All items', '8'),
    (Icons.schedule, 'Expiring soon', '2'),
    (Icons.cancel_outlined, 'Expired', '1'),
    (Icons.apps, 'Kitchenly', null),
    (Icons.apps, 'Ledgerly', null),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('All items'),
        actions: [
          const SizedBox(
            width: 260,
            child: YaruSearchField(hintText: 'Search', autofocus: false),
          ),
          const SizedBox(width: 8),
          YaruIconButton(
            icon: const Icon(Icons.file_open_outlined),
            tooltip: 'Import (Ctrl+I)',
            onPressed: () {},
          ),
          YaruIconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New item (Ctrl+N)',
            onPressed: () {},
          ),
          YaruIconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Lock (Ctrl+L)',
            onPressed: () {},
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 220,
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                for (final (i, (icon, label, count)) in _sections.indexed) ...[
                  if (i == 3)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
                      child: Text('Apps', style: theme.textTheme.labelMedium),
                    ),
                  YaruMasterTile(
                    selected: i == _section,
                    leading: Icon(icon),
                    title: Text(label),
                    trailing: count == null ? null : Text(count),
                    onTap: () => setState(() => _section = i),
                  ),
                ],
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          SizedBox(
            width: 340,
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: spikeItems.length,
              itemBuilder: (context, i) {
                final item = spikeItems[i];
                return YaruMasterTile(
                  selected: i == _selected,
                  leading: Icon(
                    item.file == null
                        ? Icons.lock_outline
                        : Icons.description_outlined,
                  ),
                  title: Text(item.title),
                  subtitle: Text('${item.type} · ${item.app}'),
                  trailing: item.expiry == null ? null : Text(item.expiry!),
                  onTap: () => setState(() => _selected = i),
                );
              },
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _Inspector(item: spikeItems[_selected])),
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
  bool _remind = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(item.title, style: theme.textTheme.headlineSmall),
        Text(item.type, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        YaruSection(
          headline: const Text('Details'),
          child: Column(
            children: [
              YaruListTile(
                title: const Text('Name'),
                trailing: SizedBox(
                  width: 260,
                  child: TextField(
                    controller: TextEditingController(text: item.title),
                  ),
                ),
              ),
              YaruListTile(
                title: const Text('Platform'),
                // Suggestions, or type your own.
                trailing: SizedBox(
                  width: 260,
                  child: YaruAutocomplete<String>(
                    initialValue: TextEditingValue(text: item.platform),
                    optionsBuilder: (value) => spikePlatforms.where(
                      (p) => p.contains(value.text.toLowerCase()),
                    ),
                  ),
                ),
              ),
              YaruListTile(
                title: const Text('Environment'),
                trailing: SizedBox(
                  width: 260,
                  child: DropdownMenu<String>(
                    width: 260,
                    initialSelection: item.environment,
                    dropdownMenuEntries: [
                      for (final e in spikeEnvironments)
                        DropdownMenuEntry(value: e, label: e),
                    ],
                  ),
                ),
              ),
              const YaruListTile(
                title: Text('Store password'),
                trailing: SizedBox(
                  width: 260,
                  child: TextField(
                    obscureText: true,
                    readOnly: true,
                    decoration: InputDecoration(hintText: '••••••••••'),
                  ),
                ),
              ),
              if (item.file case final file?)
                YaruListTile(title: const Text('File'), trailing: Text(file)),
              YaruListTile(
                title: const Text('Expires'),
                trailing: Text(item.expiry ?? 'No expiry date'),
              ),
              YaruListTile(
                title: const Text('Remind me'),
                trailing: YaruSwitch(
                  value: _remind,
                  onChanged: (v) => setState(() => _remind = v),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(onPressed: () {}, child: const Text('Export…')),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: () {}, child: const Text('Save')),
          ],
        ),
      ],
    );
  }
}
